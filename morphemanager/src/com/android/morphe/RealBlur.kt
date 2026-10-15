// Copyright (C) 2026 Samaksh Kamboj
// SPDX-License-Identifier: Apache-2.0
package com.android.morphe

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import android.os.SystemClock
import android.util.AttributeSet
import android.view.Choreographer
import android.view.View
import android.view.ViewTreeObserver
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.viewinterop.AndroidView
import kotlin.math.max

/**
 * Navbar-only real backdrop blur.
 *
 * Snapshots the pixels behind the floating nav pill from the activity root
 * and draws them back GPU-blurred. Used ONLY by the glass navbar — other
 * surfaces stay solid/translucent so the snapshot cost is paid once.
 *
 * Refresh discipline (lag-safe by construction):
 * - No ticker loop: re-snapshot is on-demand only (attach / size change /
 *   [updateKey] / any scroll in the window) plus a slow idle cadence.
 * - While content moves, captures stream every vsync frame via
 *   Choreographer instead of stepping behind scrolls.
 * - Capture runs on a frame callback, never synchronously inside draw.
 * - Heavy downsample (8 = 1/64 px) + small radius: cheap upload, cheap
 *   GPU blur, same frosted read under the tint veil.
 * - Hardware layer so the RenderEffect result is GPU-cached.
 */
@Composable
fun RealBlurBackdrop(
    tint: Color,
    modifier: Modifier = Modifier,
    blurRadiusPx: Float = 20f,
    updateKey: Any = Unit,
    downsample: Int = 8
) {
    Box(modifier = modifier) {
        AndroidView(
            factory = { context ->
                BackdropBlurView(context).also {
                    it.blurRadiusPx = blurRadiusPx
                    it.downsample = downsample
                }
            },
            update = { view ->
                view.blurRadiusPx = blurRadiusPx
                @Suppress("UNUSED_EXPRESSION")
                updateKey
                view.requestRefresh()
            },
            modifier = Modifier.fillMaxSize()
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(tint)
        )
    }
}

/**
 * Snapshots the activity root behind this view and draws it blurred.
 * Draws nothing until the first snapshot lands (transparent).
 */
class BackdropBlurView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    var blurRadiusPx: Float = 20f
        set(value) {
            if (field != value) {
                field = value
                applyRenderEffect()
            }
        }
    var downsample: Int = 8
        set(value) {
            val coerced = value.coerceIn(4, 8)
            if (field != coerced) {
                field = coerced
                snapshot?.recycle()
                snapshot = null
            }
        }

    private var snapshot: Bitmap? = null
    private val snapshotCanvas = Canvas()
    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val drawRect = android.graphics.Rect()
    private var attached = false
    private var lastCaptureMs = 0L
    private var lastTriggerMs = 0L
    private var frameScheduled = false
    private var idleScheduled = false
    private var scrollObserver: ViewTreeObserver? = null
    private val choreographer = Choreographer.getInstance()
    private val frameCallback = Choreographer.FrameCallback {
        frameScheduled = false
        if (!attached || !isAttachedToWindow) return@FrameCallback
        val now = SystemClock.uptimeMillis()
        if (now - lastTriggerMs > ACTIVE_WINDOW_MS) return@FrameCallback
        if (now - lastCaptureMs < ACTIVE_INTERVAL_MS) {
            scheduleFrame()
            return@FrameCallback
        }
        refresh()
        scheduleFrame()
    }
    private val idleRunnable = Runnable {
        idleScheduled = false
        if (!attached || !isAttachedToWindow) return@Runnable
        val now = SystemClock.uptimeMillis()
        if (now - lastTriggerMs < ACTIVE_WINDOW_MS) {
            scheduleIdle()
            return@Runnable
        }
        if (now - lastCaptureMs >= IDLE_INTERVAL_MS) refresh()
        scheduleIdle()
    }
    private val scrollListener = ViewTreeObserver.OnScrollChangedListener {
        requestRefresh()
    }

    companion object {
        private const val ACTIVE_INTERVAL_MS = 16L
        private const val IDLE_INTERVAL_MS = 400L
        private const val ACTIVE_WINDOW_MS = 600L
    }

    init {
        setWillNotDraw(false)
        setLayerType(LAYER_TYPE_HARDWARE, null)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        attached = true
        applyRenderEffect()
        try {
            rootView?.viewTreeObserver
                ?.takeIf { it.isAlive }
                ?.let {
                    it.addOnScrollChangedListener(scrollListener)
                    scrollObserver = it
                }
        } catch (_: Exception) {
            // Best-effort: blur still refreshes via updateKey/size changes.
        }
        requestRefresh()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        attached = false
        try {
            val vto = scrollObserver?.takeIf { it.isAlive }
                ?: rootView?.viewTreeObserver?.takeIf { it.isAlive }
            vto?.removeOnScrollChangedListener(scrollListener)
        } catch (_: Exception) {
        }
        scrollObserver = null
        choreographer.removeFrameCallback(frameCallback)
        frameScheduled = false
        removeCallbacks(idleRunnable)
        idleScheduled = false
        removeCallbacks(null)
        snapshot?.recycle()
        snapshot = null
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw || h != oldh) requestRefresh()
    }

    private fun applyRenderEffect() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && attached) {
            try {
                if (blurRadiusPx < 1f) {
                    setRenderEffect(null)
                } else {
                    setRenderEffect(
                        RenderEffect.createBlurEffect(
                            blurRadiusPx.coerceIn(1f, 64f),
                            blurRadiusPx.coerceIn(1f, 64f),
                            Shader.TileMode.CLAMP
                        )
                    )
                }
            } catch (_: Exception) {
                // No RenderEffect: snapshot stays sharp, tint covers.
            }
        }
    }

    fun requestRefresh() {
        if (!attached || width <= 0 || height <= 0 || !isAttachedToWindow) return
        lastTriggerMs = SystemClock.uptimeMillis()
        scheduleFrame()
        scheduleIdle()
    }

    private fun scheduleFrame() {
        if (!frameScheduled && attached && isAttachedToWindow) {
            frameScheduled = true
            choreographer.postFrameCallback(frameCallback)
        }
    }

    private fun scheduleIdle() {
        if (!idleScheduled && attached && isAttachedToWindow) {
            idleScheduled = true
            postDelayed(idleRunnable, IDLE_INTERVAL_MS)
        }
    }

    fun refresh() {
        if (!attached || width <= 0 || height <= 0 || !isAttachedToWindow) return
        val root = rootView ?: return
        lastCaptureMs = SystemClock.uptimeMillis()
        try {
            val selfPos = IntArray(2)
            val rootPos = IntArray(2)
            getLocationInWindow(selfPos)
            root.getLocationInWindow(rootPos)
            val left = selfPos[0] - rootPos[0]
            val top = selfPos[1] - rootPos[1]

            val sw = max(1, width / downsample)
            val sh = max(1, height / downsample)
            var bmp = snapshot
            if (bmp == null || bmp.isRecycled || bmp.width != sw || bmp.height != sh) {
                bmp?.takeIf { !it.isRecycled }?.recycle()
                bmp = Bitmap.createBitmap(sw, sh, Bitmap.Config.ARGB_8888)
                snapshot = bmp
            }
            val bitmap = bmp ?: return
            snapshotCanvas.setBitmap(bitmap)
            snapshotCanvas.save()
            val scale = 1f / downsample
            snapshotCanvas.scale(scale, scale)
            snapshotCanvas.translate(-left.toFloat(), -top.toFloat())
            // Hide self so the capture holds only the backdrop, never this
            // view's own last frame (no feedback smear).
            val was = visibility
            visibility = INVISIBLE
            try {
                root.draw(snapshotCanvas)
            } finally {
                visibility = was
            }
            snapshotCanvas.restore()
            snapshotCanvas.setBitmap(null)
            invalidate()
        } catch (_: Exception) {
            // Capture is best-effort; the tint layer still legibilizes text.
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val bitmap = snapshot
        if (bitmap != null && !bitmap.isRecycled) {
            drawRect.set(0, 0, width, height)
            canvas.drawBitmap(
                bitmap,
                null,
                drawRect,
                bitmapPaint
            )
        }
    }
}
