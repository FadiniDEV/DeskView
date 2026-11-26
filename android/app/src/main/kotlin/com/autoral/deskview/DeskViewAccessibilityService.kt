package com.autoral.deskview

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
import android.view.accessibility.AccessibilityEvent

/**
 * Serviço de Acessibilidade oficial do Android para execução autorizada de toques,
 * arrastos (swipes/scrolls) e teclas de sistema quando o Android atua como Host DeskView.
 */
class DeskViewAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: DeskViewAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Eventos de janela observados apenas quando necessário para foco de texto
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }

    fun injectTap(x: Float, y: Float, durationMs: Long = 45L): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x.coerceAtLeast(0f), y.coerceAtLeast(0f)) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    fun injectSwipe(
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
        durationMs: Long = 160L
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply {
            moveTo(startX.coerceAtLeast(0f), startY.coerceAtLeast(0f))
            lineTo(endX.coerceAtLeast(0f), endY.coerceAtLeast(0f))
        }
        val stroke = GestureDescription.StrokeDescription(path, 0L, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    fun executeSystemAction(winVirtualKey: Int): Boolean {
        return when (winVirtualKey) {
            0x1B -> performGlobalAction(GLOBAL_ACTION_BACK) // ESC -> Voltar no Android
            0x5B, 0x5C -> performGlobalAction(GLOBAL_ACTION_HOME) // Win -> Home no Android
            0x70 -> performGlobalAction(GLOBAL_ACTION_RECENTS) // F1 -> Recentes
            else -> false
        }
    }
}
