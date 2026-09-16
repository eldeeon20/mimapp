package com.example.pr_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Interruptor de hombre muerto del ping a Colab (NO es servicio):
/// el servicio rearma esta alarma en cada ping OK (+90s). Si la app
/// muere (barrida, ROM, crash), nadie rearma y la alarma dispara acá:
/// se baja la 777 congelada (mentiría "ACTIVO") y se postea aviso con
/// Abrir para que el usuario abra la app o cae la celda.
/// Si el ping sigue vivo (alarma vieja en carrera), se ignora.
class AlarmaColab : BroadcastReceiver() {

    companion object {
        const val ACCION = "pr_app.ALARMA_COLAB"
        const val CODIGO = 21
        const val UMBRAL_MS = 150_000L
        const val ID_ESTADO = 777
    }

    override fun onReceive(ctx: Context, intent: Intent?) {
        if (intent?.action != ACCION) return
        try {
            val p = ctx.getSharedPreferences(
                ServicioMimapp.PREFS, Context.MODE_PRIVATE
            )
            val ultimo = p.getLong("lastPingMs", 0L)
            if (System.currentTimeMillis() - ultimo < UMBRAL_MS) {
                return // ping vivo: alarma vieja, se ignora
            }
        } catch (_: Throwable) {}
        try {
            ctx.getSystemService(android.app.NotificationManager::class.java)
                ?.cancel(ID_ESTADO)
        } catch (_: Throwable) {}
        try {
            Notis.avisarAbrir(
                ctx,
                "Colab sin ping",
                "La app murió: abrila o cae la celda",
            )
        } catch (_: Throwable) {}
    }
}
