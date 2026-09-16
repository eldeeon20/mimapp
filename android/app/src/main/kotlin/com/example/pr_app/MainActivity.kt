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
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class MainActivity : AudioServiceActivity() {
    private val CANAL = "pr_app/nativo"
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
                    val m = (llamada.arguments as? Map<*, *>) ?: emptyMap<Any, Any>()
                    val expiryIso = m["expiryIso"] as? String ?: ""
                    var expiryMs = 0L
                    try {
                        val fmt = SimpleDateFormat(
                            "yyyy-MM-dd'T'HH:mm:ss", Locale.US
                        ).apply { timeZone = TimeZone.getTimeZone("UTC") }
                        // Dart manda con milisegundos (00.000) y a veces con
                        // zona (+00:00/Z): se pelan o el parse rompe y el
                        // vencimiento queda en 0 (token jamás se refresca).
                        val limpio = expiryIso.substringBefore("+")
                            .substringBefore("Z").substringBefore(".")
                        fmt.parse(limpio)?.let { expiryMs = it.time }
                    } catch (_: Exception) {}
                    val i = Intent(this, ServicioMimapp::class.java)
                        .setAction(ServicioMimapp.ACCION_START_PING)
                        .putExtra("endpoint", m["endpoint"] as? String ?: "")
                        .putExtra("accessToken", m["accessToken"] as? String ?: "")
                        .putExtra("refreshToken", m["refreshToken"] as? String ?: "")
                        .putExtra("expiryMs", expiryMs)
                        .putExtra("clientId", m["clientId"] as? String ?: "")
                        .putExtra("clientSecret", m["clientSecret"] as? String ?: "")
                    arrancar(null, i)
                    res.success(true)
                }
                "stopPing" -> {
                    arrancar(ServicioMimapp.ACCION_STOP_PING, null)
                    res.success(true)
                }
                "estado" -> {
                    val e = ServicioMimapp.estado()
                    res.success(e)
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
        val i = yaArmado ?: Intent(this, ServicioMimapp::class.java).setAction(accion)
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(i)
        } else {
            startService(i)
        }
    }
}
