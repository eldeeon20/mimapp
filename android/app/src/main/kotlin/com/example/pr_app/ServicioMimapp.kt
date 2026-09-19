package com.example.pr_app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren

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
        /// Canal SILENCIOSO (IMPORTANCE_MIN): la 888 existe por ley
        /// (foreground) pero no suena, no vibra y queda minimizada.
        /// ID nuevo a propósito: el canal viejo queda huérfano en
        /// dispositivos ya instalados (inofensivo).
        const val CANAL_ID = "pr_app_servicio"
        const val CANAL_NOMBRE = "pr_app"
        const val ID_SERVICIO = 888
        const val ID_ESTADO = 777
        const val ACCION_PRENDER = "pr_app.PRENDER"
        const val ACCION_SALIR_TOTAL = "pr_app.SALIR_TOTAL"
        const val ACCION_CERRAR_STATUS = "pr_app.CERRAR_STATUS"
        const val ACCION_START_PING = "pr_app.START_PING"
        const val ACCION_UPDATE_TOKEN = "pr_app.UPDATE_TOKEN"
        const val ACCION_PING_DART = "pr_app.PING_DART"
        const val ACCION_STOP_PING = "pr_app.STOP_PING"
        const val ACCION_STOP = "pr_app.STOP"
        /// La UI vive en otro proceso (`:ping`): el estado viaja por
        /// broadcast. La UI pide con PEDIR_ESTADO; el servicio responde
        /// y además empuja solo en cada tick/cambio con ESTADO.
        const val ACCION_PEDIR_ESTADO = "pr_app.PEDIR_ESTADO"
        const val ACCION_ESTADO = "pr_app.ESTADO"

        const val PREFS = "colab_ping"
        const val INTERVALO_MS = 60_000L
        const val LIMITE_24H_MS = 24L * 3600L * 1000L
        /// Interruptor de hombre muerto: se rearma en cada ping OK. Si
        /// la app muere, AlarmaColab avisa para abrirla o cae la celda.
        const val ALARMA_MS = 90_000L

        @Volatile var endpoint: String = ""
        // Reloj: Kotlin jamás recibe tokens (ni access, ni refresh, ni
        // secret, ni expiración). Solo endpoint + clientId para mostrar.
        @Volatile var clientId: String = ""
        @Volatile var inicioMs: Long = 0L
        @Volatile var pingsOk: Int = 0
        /// Duelo de modos: cuántos OK por modo (nuestro vs CLI).
        @Volatile var okNuestro: Int = 0
        @Volatile var okCli: Int = 0
        @Volatile var errNuestro: String = ""
        @Volatile var errCli: String = ""
        /// Solo avisos: el ping lo hace Dart puro; Kotlin no pinea,
        /// solo frente + 888 con el duelo que empuja Dart.
        @Volatile var soloAvisos: Boolean = false
        /// Último duelo Dart para la 888.
        @Volatile var dueloDart: String = ""
        @Volatile var vivo: Boolean = false
        @Volatile var ultimoError: String = ""
        @Volatile var ultimaParada: String = ""
        /// Log del último ping (visible en la 888 + logcat): código,
        /// latencia y hora. Ej: "200 · 1234ms · 14:22:31".
        @Volatile var ultimoPing: String = ""
        const val TAG_LOG = "ColabPing"
        /// Endpoint que pineaba al parar (no se borra en pararPing para
        /// que la UI desasigne la celda muerta; se limpia en X/arranque).
        @Volatile var ultimoEndpoint: String = ""

        fun estado(): Map<String, Any> = mapOf(
            "vivo" to vivo,
            "endpoint" to endpoint,
            "ultimoEndpoint" to ultimoEndpoint,
            "inicioMs" to inicioMs,
            "pingsOk" to pingsOk,
            "okNuestro" to okNuestro,
            "okCli" to okCli,
            "errNuestro" to errNuestro,
            "errCli" to errCli,
            "ultimoError" to ultimoError,
            "ultimaParada" to ultimaParada,
            "ultimoPing" to ultimoPing,
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
                .putExtra("ultimoPing", ultimoPing)
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
                // Reloj: los tokens ya no entran. Se ignora (queda por
                // compatibilidad con apps viejas que lo empujan).
                if (endpoint.isEmpty()) {
                    cargarBundle()?.let {
                        endpoint = it.endpoint
                        if (clientId.isEmpty()) clientId = it.clientId
                    }
                }
                if (intent.hasExtra("endpoint")) guardarBundle(intent)
                if (!vivo && endpoint.isNotEmpty()) {
                    empezarPing()
                }
                return START_STICKY
            }
            ACCION_PING_DART -> {
                // Push de Dart (único que pinea): duelo + rearma watchdog.
                if (intent.hasExtra("endpoint") &&
                    (intent.getStringExtra("endpoint") ?: "").isNotEmpty()
                ) {
                    guardarBundle(intent)
                }
                pingDart(
                    (intent.getIntExtra("okN", 0)),
                    (intent.getStringExtra("errN") ?: ""),
                    (intent.getIntExtra("okC", 0)),
                    (intent.getStringExtra("errC") ?: ""),
                    (intent.getIntExtra("pings", 0)),
                )
                return START_STICKY
            }
            ACCION_STOP_PING -> {
                // Celda soltada: se frena el ping (Dart ya frenó el suyo).
                pararPing("celda soltada")
                return START_NOT_STICKY
            }
        }
        // Restart STICKY pelado (el sistema mató `:ping`): retomar del
        // bundle guardado. Sin bundle no queda servicio (el frente ya se
        // aseguró arriba: se detiene legal, sin
        // ForegroundServiceDidNotStartInTimeException).
        val b = cargarBundle()
        if (b != null) {
            endpoint = b.endpoint
            clientId = b.clientId
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
        val clientId: String,
    )

    private fun prefs() =
        getSharedPreferences(PREFS, MODE_PRIVATE)

    private fun guardarBundle(i: Intent) {
        // Reloj: jamás se guardan tokens. Si el intent trae (app
        // vieja), se ignoran y se borran los viejos del prefs.
        // Endpoint saneado: espacios/saltos en la URL → 400 del TFE.
        val epLimpio = i.getStringExtra("endpoint")
            ?.replace(Regex("\\s+"), "") ?: ""
        val traeEndpoint = i.hasExtra("endpoint") && epLimpio.isNotEmpty()
        if (traeEndpoint) endpoint = epLimpio
        if (i.hasExtra("clientId")) {
            clientId = i.getStringExtra("clientId") ?: clientId
        }
        // Solo avisos por defecto: Kotlin jamás pinea.
        if (i.hasExtra("soloAvisos")) {
            soloAvisos = i.getBooleanExtra("soloAvisos", true)
        } else if (!prefs().contains("soloAvisos")) {
            soloAvisos = true
        }
        try {
            val e = prefs().edit()
            if (traeEndpoint) e.putString("endpoint", endpoint)
            if (i.hasExtra("clientId")) e.putString("clientId", clientId)
            e.putBoolean("soloAvisos", soloAvisos)
            // Limpieza: tokens de versiones viejas, fuera.
            e.remove("accessToken")
            e.remove("refreshToken")
            e.remove("expiryMs")
            e.remove("clientSecret")
            e.apply()
        } catch (_: Throwable) {}
    }

    private fun cargarBundle(): Bundle? {
        return try {
            val p = prefs()
            val ep = (p.getString("endpoint", "") ?: "")
                .replace(Regex("\\s+"), "")
            if (ep.isEmpty()) return null
            if (p.contains("soloAvisos")) {
                soloAvisos = p.getBoolean("soloAvisos", true)
            } else {
                soloAvisos = true
            }
            Bundle(
                ep,
                p.getString("clientId", "") ?: "",
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun borrarBundle() {
        endpoint = ""
        clientId = ""
        ultimoEndpoint = ""
        try { prefs().edit().clear().apply() } catch (_: Throwable) {}
    }

    // ---------------- frente y notificaciones ----------------

    private fun crearCanal() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        try {
            nm.deleteNotificationChannel("pr_app_channel")
        } catch (_: Throwable) {}
        nm.createNotificationChannel(
            NotificationChannel(
                CANAL_ID, CANAL_NOMBRE,
                NotificationManager.IMPORTANCE_MIN
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
            .setStyle(
                androidx.core.app.NotificationCompat.BigTextStyle()
                    .bigText(cuerpo)
            )
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
        if (soloAvisos && dueloDart.isNotEmpty()) {
            cuerpo += "\n$dueloDart"
        }
        if (ultimoError.isNotEmpty()) {
            cuerpo += " · error: $ultimoError"
        }
        if (ultimoPing.isNotEmpty()) {
            cuerpo += "\núltimo: $ultimoPing"
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
        // Reloj: Kotlin jamás pinea ni toca tokens. Solo frente +
        // 888 y watchdog sobre los pushes de Dart (único que pinea).
        if (endpoint.isEmpty()) {
            updFrenteSinPing("sin endpoint")
            return
        }
        scope.coroutineContext.cancelChildren()
        inicioMs = System.currentTimeMillis()
        pingsOk = 0
        ultimoError = ""
        ultimaParada = ""
        ultimoEndpoint = endpoint
        vivo = true
        arrancarFrente()
        actualizar888()
    }

    /// Push de Dart con el duelo del ping (ok/error por modo).
    /// Rearma el watchdog: si Dart deja de pushear, la alarma avisa
    /// "abrí la app o cae la celda". Kotlin jamás pinea.
    private fun pingDart(
        okN: Int,
        errN: String,
        okC: Int,
        errC: String,
        pings: Int,
    ) {
        if (!vivo) return
        okNuestro = okN
        errNuestro = errN
        okCli = okC
        errCli = errC
        pingsOk = pings
        ultimoError = ""
        dueloDart = "dart nuestro $okN" +
            (if (errN.isNotEmpty()) " [$errN]" else "") +
            " · cli $okC" +
            (if (errC.isNotEmpty()) " [$errC]" else "")
        marcarPing()
        actualizar888()
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
        // Al terminar se limpia el error: si no queda fijo en la 888.
        ultimoError = ""
        errNuestro = ""
        errCli = ""
        try { prefs().edit().clear().apply() } catch (_: Throwable) {}
        // Último parte a la UI antes de detenerse (celda muerta).
        difundirEstado()
        frente = false
        // Sin ping no hay alarma que rearmar: se desarma (si no,
        // avisaría "abrí la app" por una celda ya muerta a propósito).
        cancelarAlarma()
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


    // ---------------- interruptor de hombre muerto ----------------

    private fun piAlarma(): PendingIntent {
        val i = Intent(this, AlarmaColab::class.java)
            .setAction(AlarmaColab.ACCION)
        val f = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getBroadcast(this, AlarmaColab.CODIGO, i, f)
    }

    /// Marca ping OK y rearma la alarma (+90s). Sin esto la alarma
    /// dispara el aviso "abrí la app o cae la celda".
    private fun marcarPing() {
        try {
            prefs().edit().putLong("lastPingMs", System.currentTimeMillis())
                .apply()
        } catch (_: Throwable) {}
        programarAlarma()
    }

    private fun programarAlarma() {
        try {
            val am = getSystemService(AlarmManager::class.java) ?: return
            val cuando =
                SystemClock.elapsedRealtime() + ALARMA_MS
            try {
                am.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP, cuando, piAlarma()
                )
            } catch (_: SecurityException) {
                // Sin permiso de exactas: respaldo inexacto (puede tardar).
                am.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP, cuando, piAlarma()
                )
            }
        } catch (_: Throwable) {}
    }

    private fun cancelarAlarma() {
        try {
            val am = getSystemService(AlarmManager::class.java) ?: return
            am.cancel(piAlarma())
        } catch (_: Throwable) {}
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
        cancelarAlarma()
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

    /// Guillotina Android 15+ para `dataSync` (6h/24h en segundo plano):
    /// si no se detiene en segundos tras este callback, el sistema
    /// crashea el servicio. Parada limpia = celda que se quita sola.
    /// En Android viejo nunca se llama (existe desde API 35).
    override fun onTimeout(startId: Int, fgsType: Int) {
        try {
            pararPing("límite sistema 6h (dataSync)")
        } catch (_: Throwable) {
            try { stopSelf() } catch (_: Throwable) {}
        }
    }
}
