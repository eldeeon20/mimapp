package com.example.pr_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLEncoder
import java.net.UnknownHostException
import javax.net.ssl.SSLException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject

/// Servicio de ping a Colab 100% nativo e independiente (estilo
/// PingService): vive en proceso `:ping`, NO depende de Flutter ni de
/// la Activity una vez iniciado. Barrer la app no lo toca.
///
/// - Crear celda → `START_PING` con el bundle (endpoint+tokens): guarda
///   en prefs plano, prende frente 888 y pineea cada 60s en coroutine IO.
/// - Bundle en prefs plano `colab_ping`: el restart STICKY lo lee y
///   retoma solo. Sin bundle no hay nada que hacer → se detiene.
/// - `UPDATE_TOKEN`: la app empuja token fresco (pisa sin resetear).
/// - Única salida: la X de la 888 (`SALIR_TOTAL`/`STOP`): borra bundle,
///   cancela loop y `stopSelf`. No hay botón detener en la app.
/// - Servicio muerto = celda que se quita sola: al parar por
///   reauth/404/24h se borra el bundle y se detiene; `ultimoEndpoint`
///   queda para que la UI desasigne la celda.
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
        const val ACCION_UPDATE_TOKEN = "pr_app.UPDATE_TOKEN"
        const val ACCION_STOP = "pr_app.STOP"
        /// La UI vive en otro proceso (`:ping`): el estado viaja por
        /// broadcast. La UI pide con PEDIR_ESTADO; el servicio responde
        /// y además empuja solo en cada tick/cambio con ESTADO.
        const val ACCION_PEDIR_ESTADO = "pr_app.PEDIR_ESTADO"
        const val ACCION_ESTADO = "pr_app.ESTADO"

        const val PREFS = "colab_ping"
        const val INTERVALO_MS = 60_000L
        const val LIMITE_24H_MS = 24L * 3600L * 1000L

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
        @Volatile var ultimoError: String = ""
        @Volatile var ultimaParada: String = ""
        /// Endpoint que pineaba al parar (no se borra en pararPing para
        /// que la UI desasigne la celda muerta; se limpia en X/arranque).
        @Volatile var ultimoEndpoint: String = ""

        fun estado(): Map<String, Any> = mapOf(
            "vivo" to vivo,
            "endpoint" to endpoint,
            "ultimoEndpoint" to ultimoEndpoint,
            "inicioMs" to inicioMs,
            "pingsOk" to pingsOk,
            "ultimoError" to ultimoError,
            "ultimaParada" to ultimaParada,
        )
    }

    private val scope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var receptorPedido: android.content.BroadcastReceiver? = null

    /// true si ya se llamó startForeground en este proceso. Tras un
    /// startForegroundService() Android EXIGE startForeground en tiempo:
    /// toda entrada en frío debe prender frente primero (incluso las de
    /// parada: se prende y se detiene, nunca se entra sin frente).
    private var frente = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        crearCanal()
        // Responde pedidos de estado de la UI (otro proceso).
        try {
            val r = object : android.content.BroadcastReceiver() {
                override fun onReceive(
                    c: android.content.Context?,
                    i: Intent?,
                ) {
                    try { difundirEstado() } catch (_: Throwable) {}
                }
            }
            receptorPedido = r
            val f = android.content.IntentFilter(ACCION_PEDIR_ESTADO)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(r, f, android.content.Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(r, f)
            }
        } catch (_: Throwable) {}
    }

    /// Empuja el estado a la UI (proceso principal) por broadcast.
    private fun difundirEstado() {
        try {
            val i = Intent(ACCION_ESTADO)
                .setPackage(packageName)
                .putExtra("vivo", vivo)
                .putExtra("endpoint", endpoint)
                .putExtra("ultimoEndpoint", ultimoEndpoint)
                .putExtra("inicioMs", inicioMs)
                .putExtra("pingsOk", pingsOk)
                .putExtra("ultimoError", ultimoError)
                .putExtra("ultimaParada", ultimaParada)
            sendBroadcast(i)
        } catch (_: Throwable) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Frente asegurado: en proceso frío (o restart) hay que llamar
        // startForeground sí o sí o Android tira
        // ForegroundServiceDidNotStartInTimeException.
        if (!frente) {
            try {
                arrancarFrente()
            } catch (_: Throwable) {}
            frente = true
        }
        when (intent?.action) {
            ACCION_SALIR_TOTAL, ACCION_STOP -> {
                // X de la 888: única salida. Borra bundle, baja todo.
                pararServicio()
                return START_NOT_STICKY
            }
            ACCION_CERRAR_STATUS -> {
                cerrarStatus()
                return START_STICKY
            }
            ACCION_START_PING -> {
                // Bundle nuevo de la app (crear celda): guarda y arranca.
                if (intent.hasExtra("endpoint")) guardarBundle(intent)
                if (endpoint.isNotEmpty()) {
                    empezarPing()
                } else {
                    // Sin datos: nada que pinear.
                    updFrenteSinPing("sin datos de celda")
                }
                return START_STICKY
            }
            ACCION_UPDATE_TOKEN -> {
                // Token fresco empujado por la app: pisa sin resetear
                // contadores, inicio ni loop. En proceso frío primero se
                // recupera la memoria del bundle (si no, el update
                // parcial no sabe la celda y no puede retomar).
                if (endpoint.isEmpty()) {
                    cargarBundle()?.let {
                        endpoint = it.endpoint
                        if (accessToken.isEmpty()) accessToken = it.accessToken
                        if (refreshToken.isEmpty()) {
                            refreshToken = it.refreshToken
                        }
                        if (expiryMs == 0L) expiryMs = it.expiryMs
                        if (clientId.isEmpty()) clientId = it.clientId
                        if (clientSecret.isEmpty()) {
                            clientSecret = it.clientSecret
                        }
                    }
                }
                if (intent.hasExtra("accessToken")) guardarBundle(intent)
                if (!vivo && endpoint.isNotEmpty() && accessToken.isNotEmpty()) {
                    empezarPing()
                }
                return START_STICKY
            }
        }
        // Restart STICKY pelado (el sistema mató `:ping`): retomar del
        // bundle guardado. Sin bundle no queda servicio (el frente ya se
        // aseguró arriba: se detiene legal, sin
        // ForegroundServiceDidNotStartInTimeException).
        val b = cargarBundle()
        if (b != null) {
            endpoint = b.endpoint
            accessToken = b.accessToken
            refreshToken = b.refreshToken
            expiryMs = b.expiryMs
            clientId = b.clientId
            clientSecret = b.clientSecret
            empezarPing()
            return START_STICKY
        }
        frente = false
        try { stopSelf() } catch (_: Throwable) {}
        return START_NOT_STICKY
    }

    /// Proceso separado + stopWithTask=false: barrer la UI no mata el
    /// servicio. Sin alarma ni relanzamiento (era parche del proceso
    /// compartido): el restart STICKY + bundle alcanza.
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
    }

    // ---------------- bundle plano ----------------

    private data class Bundle(
        val endpoint: String,
        val accessToken: String,
        val refreshToken: String,
        val expiryMs: Long,
        val clientId: String,
        val clientSecret: String,
    )

    private fun prefs() =
        getSharedPreferences(PREFS, MODE_PRIVATE)

    private fun guardarBundle(i: Intent) {
        // Solo se pisa lo que el intent TRAE: en proceso frío las
        // variables están vacías y un update parcial (UPDATE_TOKEN sin
        // endpoint) jamás debe borrar lo guardado (eso mataba la celda
        // al cambiar el token con `:ping` caído).
        // Endpoint saneado: espacios/saltos en la URL → 400 del TFE.
        val epLimpio = i.getStringExtra("endpoint")
            ?.replace(Regex("\\s+"), "") ?: ""
        val traeEndpoint = i.hasExtra("endpoint") && epLimpio.isNotEmpty()
        if (traeEndpoint) endpoint = epLimpio
        if (i.hasExtra("accessToken")) {
            accessToken = i.getStringExtra("accessToken") ?: accessToken
        }
        if (i.hasExtra("refreshToken")) {
            refreshToken = i.getStringExtra("refreshToken") ?: refreshToken
        }
        if (i.hasExtra("expiryMs")) {
            expiryMs = i.getLongExtra("expiryMs", expiryMs)
        }
        if (i.hasExtra("clientId")) {
            clientId = i.getStringExtra("clientId") ?: clientId
        }
        if (i.hasExtra("clientSecret")) {
            clientSecret = i.getStringExtra("clientSecret") ?: clientSecret
        }
        try {
            val e = prefs().edit()
            if (traeEndpoint) e.putString("endpoint", endpoint)
            if (i.hasExtra("accessToken")) e.putString("accessToken", accessToken)
            if (i.hasExtra("refreshToken")) {
                e.putString("refreshToken", refreshToken)
            }
            if (i.hasExtra("expiryMs")) e.putLong("expiryMs", expiryMs)
            if (i.hasExtra("clientId")) e.putString("clientId", clientId)
            if (i.hasExtra("clientSecret")) {
                e.putString("clientSecret", clientSecret)
            }
            e.apply()
        } catch (_: Throwable) {}
    }

    private fun cargarBundle(): Bundle? {
        return try {
            val p = prefs()
            val ep = (p.getString("endpoint", "") ?: "")
                .replace(Regex("\\s+"), "")
            if (ep.isEmpty()) return null
            Bundle(
                ep,
                p.getString("accessToken", "") ?: "",
                p.getString("refreshToken", "") ?: "",
                p.getLong("expiryMs", 0L),
                p.getString("clientId", "") ?: "",
                p.getString("clientSecret", "") ?: "",
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun borrarBundle() {
        endpoint = ""
        accessToken = ""
        refreshToken = ""
        expiryMs = 0L
        clientId = ""
        clientSecret = ""
        ultimoEndpoint = ""
        try { prefs().edit().clear().apply() } catch (_: Throwable) {}
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
        return androidx.core.app.NotificationCompat.Builder(this, CANAL_ID)
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
            nm.notify(ID_SERVICIO, notiServicio(t, c))
        } catch (_: Throwable) {}
        // Espejo para la UI (otro proceso): cada tick/cambio.
        difundirEstado()
    }

    private fun texto888(): Pair<String, String> {
        if (!vivo || endpoint.isEmpty()) {
            val why = ultimaParada.ifEmpty { "sin ping" }
            return "Secure App" to "Servicio activo · $why"
        }
        var cuerpo = "$endpoint · ${formatoDur(System.currentTimeMillis() - inicioMs)} · $pingsOk pings"
        if (ultimoError.isNotEmpty()) {
            cuerpo += " · error: $ultimoError"
        }
        return "Secure App · Colab vivo" to cuerpo
    }

    private fun updFrenteSinPing(motivo: String) {
        vivo = false
        ultimaParada = motivo
        arrancarFrente()
    }

    // ---------------- ping Colab (HTTP, como el CLI) ----------------

    private fun empezarPing() {
        if (endpoint.isEmpty() || accessToken.isEmpty()) {
            updFrenteSinPing(
                if (endpoint.isEmpty()) "sin endpoint"
                else "sin token: reautenticar en Colab"
            )
            return
        }
        scope.coroutineContext.cancelChildren()
        inicioMs = System.currentTimeMillis()
        pingsOk = 0
        consec4xx = 0
        ultimoError = ""
        ultimaParada = ""
        ultimoEndpoint = endpoint
        vivo = true
        arrancarFrente()
        scope.launch {
            hacerPing()
            while (isActive && vivo) {
                delay(INTERVALO_MS)
                if (!vivo) break
                hacerPing()
            }
        }
    }

    /// Celda muerta (reauth/404/24h): servicio muerto = celda que se
    /// quita sola. Borra bundle, detiene loop y se detiene (sin bundle
    /// no queda servicio). `ultimoEndpoint` queda para la UI.
    private fun pararPing(origen: String) {
        vivo = false
        val ep = endpoint.ifEmpty { ultimoEndpoint }
        ultimaParada = if (origen.isNotEmpty()) origen else "ping detenido"
        ultimoEndpoint = ep
        endpoint = ""
        inicioMs = 0L
        consec4xx = 0
        try { prefs().edit().clear().apply() } catch (_: Throwable) {}
        accessToken = ""
        refreshToken = ""
        expiryMs = 0L
        // Último parte a la UI antes de detenerse (celda muerta).
        difundirEstado()
        frente = false
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                stopForeground(Service.STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {}
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.cancel(ID_SERVICIO)
        } catch (_: Throwable) {}
        try { stopSelf() } catch (_: Throwable) {}
    }

    // GET EXACTO del CLI/vscode: Bearer + X-Colab-Tunnel, NADA más.
    // Devuelve (código, body recortado en 4xx). -1 = ReadTimeout tras
    // conectar = éxito CLI (el TFE anotó actividad y la VM no contesta).
    // SocketTimeout SIN conectar = se lanza (neutro, reintenta).
    private fun pingCodigo(ep: String, token: String): Pair<Int, String> {
        val url = URL("https://colab.research.google.com/tun/m/$ep/keep-alive/")
        val c = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 10_000
            readTimeout = 10_000
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("X-Colab-Tunnel", "Google")
        }
        var conectado = false
        try {
            c.connect()
            conectado = true
            val code = c.responseCode
            var body = ""
            if (code in 400..599) {
                try {
                    body = c.errorStream?.bufferedReader()?.use {
                        it.readText()
                    }?.replace(Regex("\\s+"), " ")?.trim()?.take(200) ?: ""
                } catch (_: Throwable) {}
            }
            try { c.inputStream?.close() } catch (_: Throwable) {}
            try { c.errorStream?.close() } catch (_: Throwable) {}
            return code to body
        } catch (e: SocketTimeoutException) {
            if (conectado) return -1 to ""
            throw e
        }
    }

    /// Causa legible por TIPO (nunca texto crudo que puede venir null
    /// y mostrar solo "red").
    private fun diagnostico(e: Throwable): String {
        return when (e) {
            is UnknownHostException -> "sin DNS/red"
            is ConnectException -> "sin conexión"
            is SocketTimeoutException -> "timeout red"
            is SSLException -> "TLS"
            else -> e.message?.take(40)?.ifEmpty { null }
                ?: e.javaClass.simpleName.ifEmpty { "red" }
        }
    }

    private fun hacerPing() {
        val ep = endpoint
        if (ep.isEmpty()) return
        if (System.currentTimeMillis() - inicioMs >= LIMITE_24H_MS) {
            pararPing("límite 24h")
            return
        }
        try {
            var token = accessToken
            if (expiryMs > 0 && System.currentTimeMillis() > expiryMs - 60_000) {
                token = refrescar()
            }
            val (code, body) = try {
                pingCodigo(ep, token)
            } catch (e: SocketTimeoutException) {
                // ConnectTimeout = no llegó al TFE: neutro, no detiene.
                consec4xx = 0
                ultimoError = diagnostico(e)
                actualizar888()
                return
            }
            if (code == -1) {
                consec4xx = 0
                pingsOk++
                ultimoError = ""
                actualizar888()
                return
            }
            if (code == 401) {
                // Token sin permiso: refrescar UNA vez y reintentar.
                // Falla de RED en el reintento ≠ reauth: no detiene.
                val (reintento, rebody) = try {
                    token = refrescar()
                    pingCodigo(ep, token)
                } catch (e: Throwable) {
                    consec4xx = 0
                    ultimoError = diagnostico(e)
                    actualizar888()
                    return
                }
                if (reintento == -1) {
                    consec4xx = 0
                    pingsOk++
                    ultimoError = ""
                    actualizar888()
                    return
                }
                if (reintento == 401) {
                    val detalle =
                        if (rebody.isNotEmpty()) " · $rebody" else ""
                    ultimoError = "reauth 401$detalle"
                    pararPing("reauth 401: reautenticar en Colab")
                    return
                }
                return procesarCodigo(reintento, rebody)
            }
            return procesarCodigo(code, body)
        } catch (e: Throwable) {
            // red/refresh: reintenta en el próximo ciclo, NO detiene.
            consec4xx = 0
            ultimoError = diagnostico(e)
            try { actualizar888() } catch (_: Throwable) {}
        }
    }

    private fun procesarCodigo(code: Int, body: String) {
        val detalle = if (body.isNotEmpty()) " · $body" else ""
        if (code == 404) {
            consec4xx++
            ultimoError = "http 404$detalle"
            if (consec4xx >= 2) {
                pararPing("celda muerta (404)")
                return
            }
        } else if (code in 400..499) {
            consec4xx++
            ultimoError = "http $code$detalle"
            if (consec4xx >= 2) {
                pararPing("celda muerta ($code)")
                return
            }
        } else {
            consec4xx = 0
            pingsOk++
            ultimoError = ""
        }
        actualizar888()
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
        if (code != 200) {
            var body = ""
            try {
                body = c.errorStream?.bufferedReader()?.use { it.readText() }
                    ?.replace(Regex("\\s+"), " ")?.trim()?.take(120) ?: ""
            } catch (_: Throwable) {}
            ultimoError =
                if (body.isNotEmpty()) "refresh http $code · $body"
                else "refresh http $code"
            throw Exception("refresh $code")
        }
        val texto = c.inputStream.bufferedReader().use { it.readText() }
        val d = JSONObject(texto)
        accessToken = d.getString("access_token")
        val expiraEn = d.optLong("expires_in", 3600L)
        expiryMs = System.currentTimeMillis() + expiraEn * 1000L
        ultimoError = ""
        // Persiste el bundle renovado (restart retoma con token vigente).
        try {
            prefs().edit()
                .putString("accessToken", accessToken)
                .putLong("expiryMs", expiryMs)
                .apply()
        } catch (_: Throwable) {}
        return accessToken
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

    /// X de la 888 (única salida): borra bundle, cancela loop, baja la
    /// 888 y se detiene. La app (otro proceso) ni se entera.
    private fun pararServicio() {
        vivo = false
        frente = false
        ultimaParada = "servicio detenido"
        try { scope.coroutineContext.cancelChildren() } catch (_: Throwable) {}
        borrarBundle()
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                stopForeground(Service.STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {}
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.cancel(ID_SERVICIO)
        } catch (_: Throwable) {}
        try { stopSelf() } catch (_: Throwable) {}
    }

    override fun onDestroy() {
        try { scope.coroutineContext.cancelChildren() } catch (_: Throwable) {}
        try {
            receptorPedido?.let { unregisterReceiver(it) }
        } catch (_: Throwable) {}
        receptorPedido = null
        super.onDestroy()
    }
}
