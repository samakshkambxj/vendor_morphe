// Copyright (C) 2026 Samaksh Kamboj
// SPDX-License-Identifier: Apache-2.0
package com.android.morphe

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * Floating liquid-glass pill navigation: real backdrop blur snapped from
 * the activity root, tonal veil, specular top-light edge, soft shadow,
 * spring-loaded sliding indicator, press squash, click haptics and per-tab
 * badge dots. Stock framework + Compose APIs only.
 */
@Composable
fun GlassNavBar(
    selected: Int,
    labels: List<String>,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    badges: List<Boolean> = List(labels.size) { false },
    barHeight: Dp = 64.dp,
) {
    val scheme = MaterialTheme.colorScheme
    val density = LocalDensity.current
    val view = LocalView.current
    var widthPx by remember { mutableFloatStateOf(0f) }
    val glide by animateFloatAsState(
        targetValue = selected.toFloat(),
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessLow,
        ),
        label = "tabGlide",
    )
    val veil = scheme.surfaceContainer.copy(alpha = 0.45f)

    Box(modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
        Box(
            Modifier
                .onGloballyPositioned { widthPx = it.size.width.toFloat() }
                .graphicsLayer {
                    shadowElevation = with(density) { 12.dp.toPx() }
                    shape = CircleShape
                    clip = false
                    ambientShadowColor = Color.Black
                    spotShadowColor = Color.Black
                }
                .background(Color.Transparent, CircleShape)
                .clip(CircleShape)
                .height(barHeight)
                .fillMaxWidth(),
        ) {
            RealBlurBackdrop(
                tint = veil,
                modifier = Modifier.fillMaxWidth().height(barHeight),
                updateKey = selected,
                lensAmount = 0.7f,
            )
            // Sliding indicator pill under the active tab.
            if (widthPx > 0f) {
                val tabW = widthPx / labels.size
                Box(
                    Modifier
                        .offset {
                            IntOffset((tabW * glide).roundToInt(), 0)
                        }
                        .width(with(density) { tabW.toDp() })
                        .fillMaxHeight()
                        .padding(6.dp)
                        .background(scheme.primaryContainer.copy(alpha = 0.85f), CircleShape),
                )
            }
            Row(Modifier.fillMaxWidth().fillMaxHeight()) {
                labels.forEachIndexed { i, label ->
                    val interactions = remember { MutableInteractionSource() }
                    val pressed by interactions.collectIsPressedAsState()
                    Box(
                        Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .graphicsLayer {
                                val s = if (pressed) 0.92f else 1f
                                scaleX = s
                                scaleY = s
                            }
                            .clip(CircleShape)
                            .clickable(
                                interactionSource = interactions,
                                indication = null,
                                onClick = {
                                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                                    onSelect(i)
                                },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            label,
                            color = if (i == selected) scheme.onPrimaryContainer
                            else scheme.onSurfaceVariant,
                            fontWeight = if (i == selected) FontWeight.SemiBold
                            else FontWeight.Medium,
                        )
                        if (badges.getOrElse(i) { false }) {
                            Box(
                                Modifier
                                    .align(Alignment.TopCenter)
                                    .padding(top = 12.dp)
                                    .offset(x = 28.dp)
                                    .size(8.dp)
                                    .clip(CircleShape)
                                    .background(scheme.tertiary),
                            )
                        }
                    }
                }
            }
        }
    }
}
