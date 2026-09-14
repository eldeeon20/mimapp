package com.example.pr_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import java.io.File
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONObject

/// Servicio en primer plano 100% nativo de mimapp (sin
/// flutter_background_service para 888/777):
/// - 888 "Secure App" foreground con X = DETIENE EL SERVICIO (corta el
///   ping, baja la 888 y hace stopSelf). La app SIGUE viva.
/// - El ping a Colab vive acá (HTTP GET /tun/m/<ep>/keep-alive/ cada 60s,
///   igual que ColabPingMotor/ColabKeepAlive en Dart y que keep_alive del
///   google-colab-cli). Si la UI se cierra, el ping continúa.
/// - La 777 (panel Estado) la postea Dart (StatusNotifier): acá NO se
///   postea 777. "Salir" de la 777 cierra la app + baja la 777 (lo hace
///   Dart); el servicio sigue.
class ServicioMimapp : Service() {

    companion object {
        const val CANAL_ID = "pr_app_channel"
        const val CANAL_NOMBRE = "pr_app"
        const val ID_SERVICIO = 888
        const val ID_ESTADO = 777
        const val ACCION_PRENDER = "pr_app.PRENDER"
        const val ACCION_SALIR_TOTAL = "pr_app.SALIR_TOTAL"
        const val ACCION_CERRAR_STATUS = "pr_app.CERRAR_STATUS"
        const val ACCION_START_PING = "pr_app.START_PING"
        const val ACCION_STOP_PING = "pr_app.STOP_PING"
        const val ACCION_STOP = "pr_app.STOP"

        @Volatile var endpoint: String = ""
        @Volatile var accessToken: String = ""
        @Volatile var refreshToken: String = ""
        @Volatile var expiryMs: Long = 0L
        @Volatile var clientId: String = ""
        @Volatile var clientSecret: String = ""
        @Volatile var inicioMs: Long = 0L
        @Volatile var pingsOk: Int = 0
        @Volatile var consec4xx: Int = 0
        @Volatile var vivo: Boolean = false

        fun estado(): Map<String, Any> = mapOf(
            "vivo" to vivo,
            "endpoint" to endpoint,
            "inicioMs" to inicioMs,
            "pingsOk" to pingsOk,
        )
    }

    private val mano = Handler(Looper.getMainLooper())
    private var contador = 0

    private val pulso = object : Runnable {
        override fun run() {
            contador++
            actualizar888()
            mano.postDelayed(this, 5000)
        }
    }

    private val pingTick = object : Runnable {
        override fun run() {
            hacerPing()
            mano.postDelayed(this, 60_000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        crearCanal()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACCION_SALIR_TOTAL -> {
                // X de la 888: detiene el servicio, la app sigue.
                pararServicio()
                return START_NOT_STICKY
            }
            ACCION_CERRAR_STATUS -> {
                cerrarStatus()
                return START_STICKY
            }
            ACCION_START_PING -> {
                endpoint = intent.getStringExtra("endpoint") ?: ""
                accessToken = intent.getStringExtra("accessToken") ?: ""
                refreshToken = intent.getStringExtra("refreshToken") ?: ""
                expiryMs = intent.getLongExtra("expiryMs", 0L)
                clientId = intent.getStringExtra("clientId") ?: ""
                clientSecret = intent.getStringExtra("clientSecret") ?: ""
                empezarPing()
                return START_STICKY
            }
            ACCION_STOP_PING -> {
                pararPing("manual")
                return START_STICKY
            }
            ACCION_STOP -> {
                pararServicio()
                return START_NOT_STICKY
            }
        }
        arrancarFrente()
        mano.removeCallbacks(pulso)
        mano.post(pulso)
        return START_STICKY
    }

    // ---------------- frente y notificaciones ----------------

    private fun crearCanal() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(
                CANAL_ID, CANAL_NOMBRE,
                NotificationManager.IMPORTANCE_LOW
            )
        )
    }

    private fun pendienteX(): PendingIntent {
        val i = Intent(this, ServicioMimapp::class.java).setAction(ACCION_SALIR_TOTAL)
        val f = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getService(this, 1, i, f)
    }

    private fun pendienteAbrir(): PendingIntent {
        val i = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val f = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getActivity(this, 2, i, f)
    }

    private fun notiServicio(titulo: String, cuerpo: String): Notification {
        return NotificationCompat.Builder(this, CANAL_ID)
            .setContentTitle(titulo)
            .setContentText(cuerpo)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(pendienteAbrir())
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "X", pendienteX())
            .build()
    }

    private fun arrancarFrente() {
        val (t, c) = texto888()
        val n = notiServicio(t, c)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                ID_SERVICIO, n,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(ID_SERVICIO, n)
        }
    }

    private fun actualizar888() {
        val (t, c) = texto888()
        try {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            nm.notify(ID_SERVICIO, notiServicio("$t · c$contador", c))
        } catch (_: Exception) {}
    }

    private fun texto888(): Pair<String, String> {
        if (!vivo || endpoint.isEmpty()) {
            return "Secure App" to "Servicio activo · sin ping"
        }
        return "Secure App · Colab vivo" to "$endpoint · ${formatoDur(System.currentTimeMillis() - inicioMs)} · $pingsOk pings"
    }

    // ---------------- ping Colab (HTTP, como el CLI) ----------------

    private fun empezarPing() {
        if (endpoint.isEmpty() || accessToken.isEmpty()) return
        mano.removeCallbacks(pingTick)
        inicioMs = System.currentTimeMillis()
        pingsOk = 0
        consec4xx = 0
        vivo = true
        arrancarFrente()
        guardarEstado()
        Thread { hacerPing() }.start()
        mano.postDelayed(pingTick, 60_000)
    }

    private fun pararPing(origen: String) {
        mano.removeCallbacks(pingTick)
        vivo = false
        guardarEstado()
        if (origen.isNotEmpty()) actualizar888()
        endpoint = ""
        inicioMs = 0L
        consec4xx = 0
    }

    private fun hacerPing() {
        val ep = endpoint
        if (ep.isEmpty()) return
        if (System.currentTimeMillis() - inicioMs >= 24L * 3600L * 1000L) {
            mano.post { pararPing("límite 24h") }
            return
        }
        try {
            var token = accessToken
            if (expiryMs > 0 && System.currentTimeMillis() > expiryMs - 60_000) {
                token = refrescar()
            }
            val url = URL("https://colab.research.google.com/tun/m/$ep/keep-alive/?authuser=0")
            val c = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 10_000
                readTimeout = 10_000
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("X-Colab-Client-Agent", "pr_app")
                setRequestProperty("X-Colab-Tunnel", "Google")
            }
            val code = try {
                c.connect()
                c.responseCode
            } catch (e: SocketTimeoutException) {
                // Como el CLI (ReadTimeout = éxito anotado por TFE): neutro.
                consec4xx = 0
                mano.post { actualizar888() }
                return
            }
            try { c.inputStream?.close() } catch (_: Exception) {}
            try { c.errorStream?.close() } catch (_: Exception) {}
            if (code in 400..499) {
                consec4xx++
                if (consec4xx >= 2) {
                    mano.post { pararPing("celda muerta ($code)") }
                    return
                }
            } else {
                consec4xx = 0
                pingsOk++
            }
            mano.post { actualizar888() }
            guardarEstado()
        } catch (_: Exception) {
            // red/timeout: reintenta en el próximo ciclo, no cuenta error.
            consec4xx = 0
        }
    }

    /// Refresca el access_token por HTTP puro (igual que ColabPingMotor).
    private fun refrescar(): String {
        val url = URL("https://oauth2.googleapis.com/token")
        val c = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 10_000
            readTimeout = 10_000
            doOutput = true
            setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        }
        val cuerpo = "refresh_token=${URLEncoder.encode(refreshToken, "UTF-8")}" +
            "&client_id=${URLEncoder.encode(clientId, "UTF-8")}" +
            "&client_secret=${URLEncoder.encode(clientSecret, "UTF-8")}" +
            "&grant_type=refresh_token"
        c.outputStream.use { it.write(cuerpo.toByteArray()) }
        val code = c.responseCode
        if (code != 200) throw Exception("refresh $code")
        val texto = c.inputStream.bufferedReader().use { it.readText() }
        val d = JSONObject(texto)
        accessToken = d.getString("access_token")
        val expiraEn = d.optLong("expires_in", 3600L)
        expiryMs = System.currentTimeMillis() + expiraEn * 1000L
        return accessToken
    }

    /// Espejo en disco con el mismo formato que espera Dart
    /// (colab/colab_ping_estado.json). Best-effort.
    private fun guardarEstado() {
        try {
            val dir = File(filesDir, "colab")
            dir.mkdirs()
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            val ahora = fmt.format(Date())
            val inicio = if (inicioMs > 0) fmt.format(Date(inicioMs)) else ""
            val j = JSONObject()
                .put("vivo", vivo)
                .put("endpoint", endpoint)
                .put("inicio", inicio)
                .put("pingsOk", pingsOk)
                .put("cuando", ahora)
            File(dir, "colab_ping_estado.json").writeText(j.toString())
        } catch (_: Exception) {}
    }

    private fun formatoDur(ms: Long): String {
        val s = (ms / 1000).toInt()
        val h = s / 3600
        val m = (s % 3600) / 60
        val r = s % 60
        if (h > 0) return "${h}h ${m}m"
        if (m > 0) return "${m}m ${r}s"
        return "${r}s"
    }

    // ---------------- salidas ----------------

    /// Solo baja la 777 (la postea Dart): NO mata nada ni corta el ping.
    private fun cerrarStatus() {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.cancel(ID_ESTADO)
        } catch (_: Exception) {}
    }

    /// Sin celda el servicio no queda: corta ping, baja 888 y se detiene.
    /// NO mata el proceso ni toca la 777 (panel de Dart). La app sigue.
    /// (También es lo que hace la X de la 888.)
    private fun pararServicio() {
        mano.removeCallbacks(pulso)
        mano.removeCallbacks(pingTick)
        vivo = false
        guardarEstado()
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
            try { stopForeground(true) } catch (_: Exception) {}
        }
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.cancel(ID_SERVICIO)
        } catch (_: Exception) {}
        try { stopSelf() } catch (_: Exception) {}
    }

    override fun onDestroy() {
        mano.removeCallbacks(pulso)
        mano.removeCallbacks(pingTick)
        super.onDestroy()
    }
}
