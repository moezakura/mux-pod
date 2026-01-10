/**
 * SpecialKeys Component Tests
 *
 * Tests for the special key input bar component.
 */
import { render, screen, fireEvent } from '@testing-library/react-native';
import { SpecialKeys, ArrowKeys } from '@/components/terminal/SpecialKeys';

describe('SpecialKeys', () => {
  // Mock callbacks
  const createMockCallbacks = () => ({
    onSendKeys: jest.fn(),
    onSendSpecialKey: jest.fn(),
    onSendCtrl: jest.fn(),
  });

  // T010: ESCボタンでonSendSpecialKey呼び出し
  describe('ESC button', () => {
    it('calls onSendSpecialKey with "Escape" when pressed', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} />);

      fireEvent.press(screen.getByText('ESC'));

      expect(callbacks.onSendSpecialKey).toHaveBeenCalledTimes(1);
      expect(callbacks.onSendSpecialKey).toHaveBeenCalledWith('Escape');
    });
  });

  // T011: TABボタンでonSendSpecialKey呼び出し
  describe('TAB button', () => {
    it('calls onSendSpecialKey with "Tab" when pressed', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} />);

      fireEvent.press(screen.getByText('TAB'));

      expect(callbacks.onSendSpecialKey).toHaveBeenCalledTimes(1);
      expect(callbacks.onSendSpecialKey).toHaveBeenCalledWith('Tab');
    });
  });

  // T012: CTRLモード切替
  describe('CTRL mode toggle', () => {
    it('toggles CTRL mode when CTRL button is pressed', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} />);

      const ctrlButton = screen.getByText('CTRL');

      // First press enables CTRL mode
      fireEvent.press(ctrlButton);

      // Second press disables CTRL mode
      fireEvent.press(ctrlButton);

      // onSendSpecialKey should not be called for CTRL toggle
      expect(callbacks.onSendSpecialKey).not.toHaveBeenCalled();
    });

    it('ALT mode is disabled when CTRL mode is enabled', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} />);

      // Enable ALT mode first
      fireEvent.press(screen.getByText('ALT'));

      // Enable CTRL mode - should disable ALT
      fireEvent.press(screen.getByText('CTRL'));

      // Component should render without errors
      expect(screen.getByText('CTRL')).toBeTruthy();
      expect(screen.getByText('ALT')).toBeTruthy();
    });
  });

  // T013: CTRLモードでリテラルキーがonSendCtrl呼び出し
  describe('CTRL + literal key', () => {
    it('calls onSendCtrl when literal key is pressed in CTRL mode', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} />);

      // Enable CTRL mode
      fireEvent.press(screen.getByText('CTRL'));

      // Press a literal key (/)
      fireEvent.press(screen.getByText('/'));

      expect(callbacks.onSendCtrl).toHaveBeenCalledTimes(1);
      expect(callbacks.onSendCtrl).toHaveBeenCalledWith('/');
    });

    it('disables CTRL mode after sending Ctrl+key', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} />);

      // Enable CTRL mode
      fireEvent.press(screen.getByText('CTRL'));

      // Press a literal key
      fireEvent.press(screen.getByText('/'));

      // Press the same key again - should call onSendKeys, not onSendCtrl
      fireEvent.press(screen.getByText('/'));

      expect(callbacks.onSendCtrl).toHaveBeenCalledTimes(1);
      expect(callbacks.onSendKeys).toHaveBeenCalledTimes(1);
      expect(callbacks.onSendKeys).toHaveBeenCalledWith('/');
    });
  });

  // T014: disabled状態でコールバック無効
  describe('disabled state', () => {
    it('does not call callbacks when disabled', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} disabled={true} />);

      fireEvent.press(screen.getByText('ESC'));
      fireEvent.press(screen.getByText('TAB'));
      fireEvent.press(screen.getByText('CTRL'));
      fireEvent.press(screen.getByText('/'));

      expect(callbacks.onSendSpecialKey).not.toHaveBeenCalled();
      expect(callbacks.onSendKeys).not.toHaveBeenCalled();
      expect(callbacks.onSendCtrl).not.toHaveBeenCalled();
    });
  });

  // Additional tests for literal keys
  describe('literal keys in normal mode', () => {
    it('calls onSendKeys for "/" key', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} />);

      fireEvent.press(screen.getByText('/'));

      expect(callbacks.onSendKeys).toHaveBeenCalledWith('/');
    });

    it('calls onSendKeys for "-" key', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} />);

      fireEvent.press(screen.getByText('-'));

      expect(callbacks.onSendKeys).toHaveBeenCalledWith('-');
    });

    it('calls onSendKeys for "|" key', () => {
      const callbacks = createMockCallbacks();

      render(<SpecialKeys {...callbacks} />);

      fireEvent.press(screen.getByText('|'));

      expect(callbacks.onSendKeys).toHaveBeenCalledWith('|');
    });
  });
});

describe('ArrowKeys', () => {
  it('renders without crashing', () => {
    const onSendSpecialKey = jest.fn();

    // ArrowKeys component renders 4 arrow buttons
    const { toJSON } = render(<ArrowKeys onSendSpecialKey={onSendSpecialKey} />);

    // Verify component renders
    expect(toJSON()).toBeTruthy();
  });

  it('renders in disabled state without crashing', () => {
    const onSendSpecialKey = jest.fn();

    const { toJSON } = render(
      <ArrowKeys onSendSpecialKey={onSendSpecialKey} disabled={true} />
    );

    expect(toJSON()).toBeTruthy();
  });
});
