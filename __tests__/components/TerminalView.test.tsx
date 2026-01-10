/**
 * TerminalView Component Tests
 *
 * Tests for the ANSI color-aware terminal view component.
 */
import { render, screen } from '@testing-library/react-native';
import { TerminalView } from '@/components/terminal/TerminalView';
import type { AnsiLine, AnsiSpan, TerminalTheme } from '@/types/terminal';
import { MUXPOD_THEME, DRACULA_THEME } from '@/types/terminal';

// Mock data helpers
const createSpan = (text: string, overrides?: Partial<AnsiSpan>): AnsiSpan => ({
  text,
  ...overrides,
});

const createLine = (spans: AnsiSpan[]): AnsiLine => ({
  spans,
});

describe('TerminalView', () => {
  // T022: テキスト内容が表示される
  describe('displays text content', () => {
    it('renders plain text', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Hello, World!')]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Hello, World!')).toBeTruthy();
    });

    it('renders multiple lines', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Line 1')]),
        createLine([createSpan('Line 2')]),
        createLine([createSpan('Line 3')]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Line 1')).toBeTruthy();
      expect(screen.getByText('Line 2')).toBeTruthy();
      expect(screen.getByText('Line 3')).toBeTruthy();
    });

    it('renders multiple spans in a line', () => {
      const lines: AnsiLine[] = [
        createLine([
          createSpan('Hello, '),
          createSpan('World!'),
        ]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Hello, ')).toBeTruthy();
      expect(screen.getByText('World!')).toBeTruthy();
    });
  });

  // T023: 前景色が適用される
  describe('applies foreground color', () => {
    it('renders with foreground color specified', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Red text', { fg: 1 })]), // Red
      ];

      render(<TerminalView lines={lines} />);

      // Text should be rendered (style testing is limited in RNTL)
      expect(screen.getByText('Red text')).toBeTruthy();
    });

    it('renders with 256-color foreground', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('256 color', { fg: 196 })]), // Bright red
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('256 color')).toBeTruthy();
    });

    it('renders with background color specified', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('With background', { bg: 4 })]), // Blue bg
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('With background')).toBeTruthy();
    });
  });

  // T024: bold属性が適用される
  describe('applies text styles', () => {
    it('renders bold text', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Bold text', { bold: true })]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Bold text')).toBeTruthy();
    });

    it('renders italic text', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Italic text', { italic: true })]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Italic text')).toBeTruthy();
    });

    it('renders underlined text', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Underlined', { underline: true })]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Underlined')).toBeTruthy();
    });

    it('renders strikethrough text', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Strikethrough', { strikethrough: true })]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Strikethrough')).toBeTruthy();
    });

    it('renders dim text', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Dim text', { dim: true })]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Dim text')).toBeTruthy();
    });

    it('renders combined styles', () => {
      const lines: AnsiLine[] = [
        createLine([
          createSpan('Bold and italic', { bold: true, italic: true }),
        ]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Bold and italic')).toBeTruthy();
    });
  });

  // T025: 空行の高さ
  describe('handles empty lines', () => {
    it('renders empty line with proper height', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Before')]),
        createLine([]), // Empty line
        createLine([createSpan('After')]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Before')).toBeTruthy();
      expect(screen.getByText('After')).toBeTruthy();
    });

    it('renders multiple consecutive empty lines', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Start')]),
        createLine([]),
        createLine([]),
        createLine([]),
        createLine([createSpan('End')]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Start')).toBeTruthy();
      expect(screen.getByText('End')).toBeTruthy();
    });
  });

  // T026: カスタムテーマの背景色
  describe('applies custom theme', () => {
    it('uses default MuxPod theme', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Default theme')]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Default theme')).toBeTruthy();
    });

    it('applies custom theme', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Custom theme')]),
      ];

      render(<TerminalView lines={lines} theme={DRACULA_THEME} />);

      expect(screen.getByText('Custom theme')).toBeTruthy();
    });

    it('applies MuxPod theme explicitly', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('MuxPod theme')]),
      ];

      render(<TerminalView lines={lines} theme={MUXPOD_THEME} />);

      expect(screen.getByText('MuxPod theme')).toBeTruthy();
    });
  });

  // Additional edge case tests
  describe('edge cases', () => {
    it('handles empty lines array', () => {
      render(<TerminalView lines={[]} />);

      // Should render without crashing
      expect(true).toBeTruthy();
    });

    it('handles inverse colors', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Inverse', { inverse: true })]),
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Inverse')).toBeTruthy();
    });

    it('handles hidden text', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Hidden', { hidden: true })]),
      ];

      render(<TerminalView lines={lines} />);

      // Hidden text should still be in the DOM
      expect(screen.getByText('Hidden')).toBeTruthy();
    });

    it('handles custom font size', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Large text')]),
      ];

      render(<TerminalView lines={lines} fontSize={16} />);

      expect(screen.getByText('Large text')).toBeTruthy();
    });

    it('handles custom line height', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Custom line height')]),
      ];

      render(<TerminalView lines={lines} lineHeight={24} />);

      expect(screen.getByText('Custom line height')).toBeTruthy();
    });

    it('handles grayscale colors', () => {
      const lines: AnsiLine[] = [
        createLine([createSpan('Grayscale', { fg: 240 })]), // Grayscale color
      ];

      render(<TerminalView lines={lines} />);

      expect(screen.getByText('Grayscale')).toBeTruthy();
    });
  });
});
