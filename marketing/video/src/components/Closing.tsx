import React from 'react';
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import { motion, palette, typography } from '../theme/tokens';
import { ParakeetMark } from './ParakeetMark';
import { SCRIPT } from '../content/script';

/**
 * Closing card — used by Demo60 and HeroLoop30 as the final 3-6 second beat.
 *
 * Paper-cream background, coral parakeet mark, ink headline, coral URL.
 * Mirrors the Hook composition's visual rhythm so the demo book-ends
 * cleanly. All copy pulled from SCRIPT.closing.
 */
export const Closing: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const markProgress = spring({
    frame: frame - 4,
    fps,
    config: motion.springSoft,
    durationInFrames: 36,
  });
  const markOpacity = interpolate(frame, [0, 24], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const markScale = interpolate(markProgress, [0, 1], [0.94, 1]);

  const headlineProgress = spring({
    frame: frame - 22,
    fps,
    config: motion.springSoft,
    durationInFrames: 36,
  });
  const headlineOpacity = interpolate(frame, [22, 38], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const headlineTranslate = interpolate(headlineProgress, [0, 1], [16, 0]);

  const urlProgress = spring({
    frame: frame - 42,
    fps,
    config: motion.springSoft,
    durationInFrames: 36,
  });
  const urlOpacity = interpolate(frame, [42, 58], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const urlTranslate = interpolate(urlProgress, [0, 1], [12, 0]);

  return (
    <AbsoluteFill style={{ backgroundColor: palette.paper }}>
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 56,
        }}
      >
        <div
          style={{
            opacity: markOpacity,
            transform: `scale(${markScale})`,
            willChange: 'transform, opacity',
          }}
        >
          <ParakeetMark size={140} color={palette.coral} />
        </div>

        <div
          style={{
            fontFamily: typography.display,
            fontSize: typography.closingHeadline,
            fontWeight: 600,
            color: palette.ink,
            letterSpacing: -1,
            textAlign: 'center',
            opacity: headlineOpacity,
            transform: `translateY(${headlineTranslate}px)`,
            willChange: 'transform, opacity',
          }}
        >
          {SCRIPT.closing.headline}
        </div>

        <div
          style={{
            fontFamily: typography.display,
            fontSize: 56,
            fontWeight: 700,
            color: palette.coral,
            letterSpacing: -1,
            opacity: urlOpacity,
            transform: `translateY(${urlTranslate}px)`,
            willChange: 'transform, opacity',
          }}
        >
          {SCRIPT.closing.wordmark}
        </div>
      </div>
    </AbsoluteFill>
  );
};
