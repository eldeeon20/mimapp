package com.example.pr_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CANAL = "pr_app/nativo"

    /// Último estado empujado por `:ping` (ver ACCION_ESTADO).
    private val estadoCache = mutableMapOf<String, Any>()
    private var estadoReceiverOn = false

    private fun escucharEstado() {
        if (estadoReceiverOn) return
        estadoReceiverOn = true
        try {
            val r = object : android.content.BroadcastReceiver() {
                override fun onReceive(
                    c: android.content.Context?,
                    i: Intent?,
                ) {
                    try {
                        if (i == null) return
                        estadoCache["vivo"] = i.getBooleanExtra("vivo", false)
                        estadoCache["endpoint"] = i.getStringExtra("endpoint") ?: ""
                        estadoCache["ultimoEndpoint"] =
                            i.getStringExtra("ultimoEndpoint") ?: ""
                        estadoCache["inicioMs"] = i.getLongExtra("inicioMs", 0L)
                        estadoCache["pingsOk"] = i.getIntExtra("pingsOk", 0)
                        estadoCache["ultimoError"] =
                            i.getStringExtra("ultimoError") ?: ""
                        estadoCache["ultimaParada"] =
                            i.getStringExtra("ultimaParada") ?: ""
                        estadoCache["ultimoPing"] =
                            i.getStringExtra("ultimoPing") ?: ""
                    } catch (_: Throwable) {}
                }
            }
            val f = android.content.IntentFilter(ServicioMimapp.ACCION_ESTADO)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(r, f, android.content.Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(r, f)
            }
        } catch (_: Throwable) {}
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Dibujar también en la zona del notch/punch-hole (evita franja negra)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        escucharEstado()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CANAL
        ).setMethodCallHandler { llamada, res ->
            when (llamada.method) {
                "prender" -> {
                    arrancar(ServicioMimapp.ACCION_PRENDER, null)
                    res.success(true)
                }
                "apagar", "stop" -> {
                    // Sin celda no queda servicio; no mata la app.
                    arrancar(ServicioMimapp.ACCION_STOP, null)
                    res.success(true)
                }
                "salirTotal" -> {
                    arrancar(ServicioMimapp.ACCION_SALIR_TOTAL, null)
                    res.success(true)
                }
                "cerrarStatus" -> {
                    arrancar(ServicioMimapp.ACCION_CERRAR_STATUS, null)
                    res.success(true)
                }
                "startPing" -> {
                    // Reloj: Kotlin jamás recibe tokens (el ping es
                    // Dart puro). Solo endpoint + clientId para mostrar.
                    val m = (llamada.arguments as? Map<*, *>) ?: emptyMap<Any, Any>()
                    val i = Intent(this, ServicioMimapp::class.java)
                        .setAction(ServicioMimapp.ACCION_START_PING)
                        .putExtra("endpoint", m["endpoint"] as? String ?: "")
                        .putExtra("clientId", m["clientId"] as? String ?: "")
                        .putExtra("soloAvisos", (m["soloAvisos"] as? Boolean) ?: true)
                    arrancar(null, i)
                    res.success(true)
                }
                "pingDart" -> {                    // Push de Dart (único que pinea): duelo + rearma watchdog.
                    val m = (llamada.arguments as? Map<*, *>) ?: emptyMap<Any, Any>()
                    val i = Intent(this, ServicioMimapp::class.java)
                        .setAction(ServicioMimapp.ACCION_PING_DART)
                        .putExtra("endpoint", m["endpoint"] as? String ?: "")
                        .putExtra("okN", (m["okN"] as? Number)?.toInt() ?: 0)
                        .putExtra("errN", m["errN"] as? String ?: "")
                        .putExtra("okC", (m["okC"] as? Number)?.toInt() ?: 0)
                        .putExtra("errC", m["errC"] as? String ?: "")
                        .putExtra("pings", (m["pings"] as? Number)?.toInt() ?: 0)
                    arrancar(null, i)
                    res.success(true)
                }
                "stopPing" -> {
                    // Celda soltada desde la app: frena el ping nativo.
                    val i = Intent(this, ServicioMimapp::class.java)
                        .setAction(ServicioMimapp.ACCION_STOP_PING)
                    arrancar(null, i)
                    res.success(true)
                }
                "estado" -> {
                    // El servicio vive en `:ping` (otro proceso): los
                    // statics locales están muertos. Se devuelve el
                    // último broadcast recibido y se pide uno fresco
                    // (llega solo; el próximo tick lo trae).
                    try {
                        sendBroadcast(
                            Intent(ServicioMimapp.ACCION_PEDIR_ESTADO)
                                .setPackage(packageName)
                        )
                    } catch (_: Throwable) {}
                    res.success(HashMap(estadoCache))
                }
                // Check de memoria/almacenamiento (Configuración →
                // Almacén): StatFs del almacenamiento interno + RAM del
                // ActivityManager. Todo en bytes (Dart formatea).
                "memoria" -> {
                    try {
                        val stat = android.os.StatFs(
                            android.os.Environment.getDataDirectory().path)
                        val bloque = stat.blockSizeLong
                        val total = stat.blockCountLong * bloque
                        val libre = stat.availableBlocksLong * bloque
                        val am = getSystemService(
                            android.content.Context.ACTIVITY_SERVICE)
                            as android.app.ActivityManager
                        val mi =
                            android.app.ActivityManager.MemoryInfo()
                        am.getMemoryInfo(mi)
                        res.success(mapOf(
                            "internaTotal" to total,
                            "internaLibre" to libre,
                            "ramTotal" to mi.totalMem,
                            "ramLibre" to mi.availMem,
                        ))
                    } catch (e: Throwable) {
                        res.error("MEMORIA", "${e.message}", null)
                    }
                }
                // Sin esto Android 12+ y las ROMs matan el servicio al
                // barrer y NO lo dejan revivir (ni alarma ni sticky).
                // Abre el ajuste para eximir a la app (una sola vez).
                "sinLimites" -> {
                    try {
                        val pm =
                            getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (pm.isIgnoringBatteryOptimizations(packageName)) {
                            res.success(true)
                        } else {
                            val i = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(i)
                            res.success(false)
                        }
                    } catch (_: Throwable) {
                        res.success(false)
                    }
                }
                "avisar" -> {
                    val m = (llamada.arguments as? Map<*, *>) ?: emptyMap<Any, Any>()
                    val id = Notis.avisar(
                        this,
                        m["titulo"] as? String ?: "Secure App",
                        m["cuerpo"] as? String ?: "",
                    )
                    res.success(id)
                }
                "quitarAviso" -> {
                    val m = (llamada.arguments as? Map<*, *>) ?: emptyMap<Any, Any>()
                    Notis.quitar(this, (m["id"] as? Number)?.toInt() ?: 0)
                    res.success(true)
                }
                "progresoAviso" -> {
                    val m = (llamada.arguments as? Map<*, *>) ?: emptyMap<Any, Any>()
                    val id = (m["id"] as? Number)?.toInt() ?: 0
                    Notis.progreso(
                        this,
                        id,
                        m["titulo"] as? String ?: "",
                        m["cuerpo"] as? String ?: "",
                        (m["progreso"] as? Number)?.toDouble(),
                        m["terminado"] as? Boolean ?: false,
                    )
                    res.success(id)
                }
                else -> res.notImplemented()
            }
        }
    }

    private fun arrancar(accion: String?, yaArmado: Intent?) {
        // Blindado: si la app está en fondo y el sistema rechaza el
        // arranque (background start), que falle mudo y NO crashee la UI.
        try {
            val i = yaArmado ?: Intent(this, ServicioMimapp::class.java).setAction(accion)
            if (Build.VERSION.SDK_INT >= 26) {
                startForegroundService(i)
            } else {
                startService(i)
            }
        } catch (_: Throwable) {}
    }
}
