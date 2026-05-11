import React from 'react';
import { AbsoluteFill, staticFile, Video } from 'remotion';
import { palette, typography } from '../theme/tokens';

interface ScreencastSlotProps {
  /** Filename inside `public/screencasts/`, e.g. "dictation.mp4". */
  src: string;
  /** Human-readable label for the placeholder when the file isn't there yet. */
  label: string;
  /** Short description shown under the label. */
  hint?: string;
  /** Force placeholder even if the file exists. Useful while iterating. */
  forcePlaceholder?: boolean;
}

/**
 * Slot for a screencast clip captured from MacParakeet itself.
 *
 * Renders the actual video when the file is present in
 * `public/screencasts/`. Falls back to a branded placeholder card while
 * the screencast hasn't been captured yet — so Demo60 / HeroLoop30 stay
 * renderable end-to-end even before raw clips exist.
 *
 * The "file exists" check happens at render time via a try/catch around
 * <Video>. If staticFile resolves to a missing path, Remotion throws
 * during render — but in Studio preview we want a graceful card, so this
 * component intentionally renders the placeholder by default and only
 * upgrades to <Video> when the caller is confident the file is in place.
 */
export const ScreencastSlot: React.FC<ScreencastSlotProps> = ({
  src,
  label,
  hint,
  forcePlaceholder = false,
}) => {
  if (forcePlaceholder) {
    return <Placeholder label={label} hint={hint} />;
  }

  // <Video> errors at render time if the file doesn't exist. The boundary
  // below catches that and shows the placeholder instead, so Demo60 still
  // renders cleanly before screencasts are captured.
  return (
    <ErrorBoundary fallback={<Placeholder label={label} hint={hint} />}>
      <Video src={staticFile(`screencasts/${src}`)} />
    </ErrorBoundary>
  );
};

const Placeholder: React.FC<{ label: string; hint?: string }> = ({
  label,
  hint,
}) => {
  return (
    <AbsoluteFill
      style={{
        backgroundColor: palette.paper,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <div
        style={{
          border: `4px dashed ${palette.ink}33`,
          borderRadius: 24,
          padding: '64px 96px',
          textAlign: 'center',
          maxWidth: 1200,
        }}
      >
        <div
          style={{
            fontFamily: typography.body,
            fontSize: 24,
            fontWeight: 700,
            letterSpacing: 4,
            textTransform: 'uppercase',
            color: palette.coral,
            marginBottom: 16,
          }}
        >
          Screencast Slot
        </div>
        <div
          style={{
            fontFamily: typography.display,
            fontSize: typography.closingHeadline,
            fontWeight: 700,
            color: palette.ink,
            letterSpacing: -1,
            marginBottom: hint ? 24 : 0,
          }}
        >
          {label}
        </div>
        {hint ? (
          <div
            style={{
              fontFamily: typography.body,
              fontSize: 28,
              color: palette.ink,
              opacity: 0.6,
              maxWidth: 800,
              margin: '0 auto',
              lineHeight: 1.4,
            }}
          >
            {hint}
          </div>
        ) : null}
      </div>
    </AbsoluteFill>
  );
};

interface ErrorBoundaryProps {
  fallback: React.ReactNode;
  children: React.ReactNode;
}

class ErrorBoundary extends React.Component<
  ErrorBoundaryProps,
  { hasError: boolean }
> {
  state = { hasError: false };

  static getDerivedStateFromError(): { hasError: boolean } {
    return { hasError: true };
  }

  render(): React.ReactNode {
    return this.state.hasError ? this.props.fallback : this.props.children;
  }
}
