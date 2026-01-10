/**
 * ConnectionStatusIndicator Unit Tests
 */
import React from 'react';
import { render, fireEvent } from '@testing-library/react-native';
import { ConnectionStatusIndicator } from '@/components/connection/ConnectionStatusIndicator';
import type { ConnectionState } from '@/types/connection';

describe('ConnectionStatusIndicator', () => {
  const createState = (overrides?: Partial<ConnectionState>): ConnectionState => ({
    connectionId: 'test-id',
    status: 'disconnected',
    ...overrides,
  });

  describe('status display', () => {
    it('should show green indicator when connected', () => {
      const state = createState({ status: 'connected' });
      const { getByTestId } = render(<ConnectionStatusIndicator state={state} />);

      const indicator = getByTestId('status-indicator');
      expect(indicator.props.style).toMatchObject(
        expect.objectContaining({ backgroundColor: '#22c55e' })
      );
    });

    it('should show red indicator when disconnected', () => {
      const state = createState({ status: 'disconnected' });
      const { getByTestId } = render(<ConnectionStatusIndicator state={state} />);

      const indicator = getByTestId('status-indicator');
      expect(indicator.props.style).toMatchObject(
        expect.objectContaining({ backgroundColor: '#ef4444' })
      );
    });

    it('should show yellow indicator when reconnecting', () => {
      const state = createState({ status: 'reconnecting' });
      const { getByTestId } = render(<ConnectionStatusIndicator state={state} />);

      const indicator = getByTestId('status-indicator');
      expect(indicator.props.style).toMatchObject(
        expect.objectContaining({ backgroundColor: '#eab308' })
      );
    });

    it('should show yellow indicator when connecting', () => {
      const state = createState({ status: 'connecting' });
      const { getByTestId } = render(<ConnectionStatusIndicator state={state} />);

      const indicator = getByTestId('status-indicator');
      expect(indicator.props.style).toMatchObject(
        expect.objectContaining({ backgroundColor: '#eab308' })
      );
    });

    it('should show red indicator when error', () => {
      const state = createState({ status: 'error' });
      const { getByTestId } = render(<ConnectionStatusIndicator state={state} />);

      const indicator = getByTestId('status-indicator');
      expect(indicator.props.style).toMatchObject(
        expect.objectContaining({ backgroundColor: '#ef4444' })
      );
    });
  });

  describe('interaction', () => {
    it('should call onPress when pressed', () => {
      const onPress = jest.fn();
      const state = createState({ status: 'connected' });
      const { getByTestId } = render(
        <ConnectionStatusIndicator state={state} onPress={onPress} />
      );

      const touchable = getByTestId('status-touchable');
      fireEvent.press(touchable);

      expect(onPress).toHaveBeenCalledTimes(1);
    });

    it('should not be pressable when onPress is not provided', () => {
      const state = createState({ status: 'connected' });
      const { queryByTestId } = render(<ConnectionStatusIndicator state={state} />);

      // onPressがない場合はtouchableがない
      const touchable = queryByTestId('status-touchable');
      expect(touchable).toBeNull();
    });
  });

  describe('details display', () => {
    it('should show label when showDetails is true', () => {
      const state = createState({ status: 'connected' });
      const { getByText } = render(
        <ConnectionStatusIndicator state={state} showDetails />
      );

      expect(getByText('接続中')).toBeTruthy();
    });

    it('should show attempt info when reconnecting', () => {
      const state = createState({
        status: 'reconnecting',
        reconnectAttempt: {
          startedAt: Date.now(),
          attemptNumber: 2,
          maxAttempts: 3,
          history: [],
        },
      });
      const { getByText } = render(
        <ConnectionStatusIndicator state={state} showDetails />
      );

      expect(getByText('再接続中 (2/3)')).toBeTruthy();
    });
  });

  describe('size variants', () => {
    it('should render small size', () => {
      const state = createState({ status: 'connected' });
      const { getByTestId } = render(
        <ConnectionStatusIndicator state={state} size="sm" />
      );

      const indicator = getByTestId('status-indicator');
      expect(indicator.props.style).toMatchObject(
        expect.objectContaining({ width: 12, height: 12 })
      );
    });

    it('should render medium size by default', () => {
      const state = createState({ status: 'connected' });
      const { getByTestId } = render(<ConnectionStatusIndicator state={state} />);

      const indicator = getByTestId('status-indicator');
      expect(indicator.props.style).toMatchObject(
        expect.objectContaining({ width: 16, height: 16 })
      );
    });

    it('should render large size', () => {
      const state = createState({ status: 'connected' });
      const { getByTestId } = render(
        <ConnectionStatusIndicator state={state} size="lg" />
      );

      const indicator = getByTestId('status-indicator');
      expect(indicator.props.style).toMatchObject(
        expect.objectContaining({ width: 20, height: 20 })
      );
    });
  });
});
