package com.example.pr_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import java.util.concurrent.atomic.AtomicInteger

/// Avisos básicos apilables SIN botones: se cierran deslizando o con
/// "Limpiar" de Android. Para mensajes o descargas futuras.
/// No son ongoing (salvo un progreso en curso) → el sistema los puede
/// descartar. No pisa 888/777 ni el rango 9000+ de Dart.
object Notis {
    const val CANAL_ID = "pr_app_avisos"
    private const val GRUPO = "pr_app_avisos"
    private val seq = AtomicInteger(2000)

    fun canal(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(
                CANAL_ID, "Avisos",
                NotificationManager.IMPORTANCE_DEFAULT
            )
        )
    }

    /// Aviso con ABRIR (tocar trae la app al frente). Para el
    /// interruptor de hombre muerto: autoCancel al tocar.
    fun avisarAbrir(ctx: Context, titulo: String, cuerpo: String): Int {
        canal(ctx)
        val id = siguienteId()
        val abrir = android.app.PendingIntent.getActivity(
            ctx, 31,
            android.content.Intent(ctx, MainActivity::class.java).apply {
                action = android.content.Intent.ACTION_MAIN
                addCategory(android.content.Intent.CATEGORY_LAUNCHER)
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                    android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                (if (android.os.Build.VERSION.SDK_INT >= 31)
                    android.app.PendingIntent.FLAG_IMMUTABLE else 0),
        )
        val n = NotificationCompat.Builder(ctx, CANAL_ID)
            .setContentTitle(titulo)
            .setContentText(cuerpo)
            .setStyle(NotificationCompat.BigTextStyle().bigText(cuerpo))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(abrir)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setGroup(GRUPO)
            .build()
        ctx.getSystemService(NotificationManager::class.java)?.notify(id, n)
        return id
    }

    /// Muestra un aviso simple y devuelve su id.
    fun avisar(ctx: Context, titulo: String, cuerpo: String): Int {
        canal(ctx)
        val id = siguienteId()
        val n = NotificationCompat.Builder(ctx, CANAL_ID)
            .setContentTitle(titulo)
            .setContentText(cuerpo)
            .setStyle(NotificationCompat.BigTextStyle().bigText(cuerpo))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setGroup(GRUPO)
            .build()
        ctx.getSystemService(NotificationManager::class.java)?.notify(id, n)
        return id
    }

    /// Progreso (ej. descargas): en curso es ongoing (no deslizable
    /// hasta terminar); terminado queda normal y deslizable.
    /// [tanto1] 0..1, null = indeterminado.
    fun progreso(
        ctx: Context,
        id: Int,
        titulo: String,
        cuerpo: String,
        tanto1: Double?,
        terminado: Boolean,
    ) {
        canal(ctx)
        val b = NotificationCompat.Builder(ctx, CANAL_ID)
            .setContentTitle(titulo)
            .setContentText(cuerpo)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setOngoing(!terminado)
            .setAutoCancel(terminado)
            .setGroup(GRUPO)
        if (!terminado) {
            if (tanto1 == null) {
                b.setProgress(0, 0, true)
            } else {
                b.setProgress(100, (tanto1.coerceIn(0.0, 1.0) * 100).toInt(), false)
            }
        }
        ctx.getSystemService(NotificationManager::class.java)?.notify(id, b.build())
    }

    fun quitar(ctx: Context, id: Int) {
        try {
            ctx.getSystemService(NotificationManager::class.java)?.cancel(id)
        } catch (_: Exception) {}
    }

    private fun siguienteId(): Int {
        while (true) {
            val id = seq.getAndIncrement()
            if (id > 7999) seq.set(2000)
            // Reserva Dart/servicio: 777, 888, 9000+.
            if (id == 777 || id == 888) continue
            return id
        }
    }
}
