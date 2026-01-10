/**
 * SSHクライアント
 *
 * react-native-ssh-sftpをラップし、SSH接続を管理する。
 */
import type { Connection } from '@/types/connection';

/**
 * SSH接続オプション
 */
export interface SSHConnectOptions {
  /** パスワード認証時のパスワード */
  password?: string;
  /** 鍵認証時の秘密鍵（PEM形式） */
  privateKey?: string;
  /** 秘密鍵のパスフレーズ */
  passphrase?: string;
}

/**
 * シェルオプション
 */
export interface ShellOptions {
  /** ターミナルタイプ */
  term?: string;
  /** カラム数 */
  cols?: number;
  /** 行数 */
  rows?: number;
}

/**
 * SSH接続イベント
 */
export interface SSHEvents {
  /** データ受信時 */
  onData: (data: string) => void;
  /** 接続クローズ時 */
  onClose: () => void;
  /** エラー発生時 */
  onError: (error: Error) => void;
}

/**
 * SSH接続エラー
 */
export class SSHConnectionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SSHConnectionError';
  }
}

/**
 * SSH認証エラー
 */
export class SSHAuthenticationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SSHAuthenticationError';
  }
}

/**
 * SSHクライアントインターフェース
 */
export interface ISSHClient {
  connect(connection: Connection, options: SSHConnectOptions): Promise<void>;
  disconnect(): Promise<void>;
  isConnected(): boolean;
  startShell(options?: ShellOptions): Promise<void>;
  write(data: string): Promise<void>;
  resize(cols: number, rows: number): Promise<void>;
  exec(command: string): Promise<string>;
  setEventHandlers(events: Partial<SSHEvents>): void;
}

/**
 * SSHクライアント実装
 */
export class SSHClient implements ISSHClient {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private client: any = null;
  private connected = false;
  private events: Partial<SSHEvents> = {};

  /**
   * 接続中かどうかを返す
   */
  isConnected(): boolean {
    return this.connected;
  }

  /**
   * SSH接続を確立する
   */
  async connect(connection: Connection, options: SSHConnectOptions): Promise<void> {
    // 接続パラメータのバリデーション
    if (!connection.host || connection.host.trim() === '') {
      throw new SSHConnectionError('Host is required');
    }
    if (!connection.username || connection.username.trim() === '') {
      throw new SSHConnectionError('Username is required');
    }
    if (connection.port < 1 || connection.port > 65535) {
      throw new SSHConnectionError('Invalid port number');
    }

    // 認証情報のバリデーション
    if (connection.authMethod === 'password' && !options.password) {
      throw new SSHAuthenticationError('Password is required for password authentication');
    }
    if (connection.authMethod === 'key' && !options.privateKey) {
      throw new SSHAuthenticationError('Private key is required for key authentication');
    }

    try {
      // react-native-ssh-sftpの動的インポート
      const SSHClientNative = (await import('react-native-ssh-sftp')).default;

      // 認証方式に応じた接続
      if (connection.authMethod === 'password') {
        // password は上のバリデーションで存在が保証されている
        this.client = await SSHClientNative.connectWithPassword(
          connection.host,
          connection.port,
          connection.username,
          options.password!
        );
      } else {
        // privateKey は上のバリデーションで存在が保証されている
        this.client = await SSHClientNative.connectWithKey(
          connection.host,
          connection.port,
          connection.username,
          options.privateKey!,
          options.passphrase
        );
      }

      this.connected = true;
    } catch (error) {
      this.connected = false;
      const message = error instanceof Error ? error.message : 'Unknown connection error';
      throw new SSHConnectionError(`Failed to connect: ${message}`);
    }
  }

  /**
   * 接続を切断する
   */
  async disconnect(): Promise<void> {
    if (this.client) {
      try {
        await this.client.disconnect();
      } catch {
        // 切断時のエラーは無視
      }
      this.client = null;
    }
    this.connected = false;
  }

  /**
   * インタラクティブシェルを開始する
   */
  async startShell(options?: ShellOptions): Promise<void> {
    if (!this.connected || !this.client) {
      throw new SSHConnectionError('Not connected');
    }

    try {
      await this.client.startShell(
        options?.term ?? 'xterm-256color',
        {
          ptyWidth: options?.cols ?? 80,
          ptyHeight: options?.rows ?? 24,
        }
      );

      // イベントハンドラの設定
      if (this.events.onData) {
        this.client.on('Shell', this.events.onData);
      }

      // Disconnectイベント時にconnectedフラグを更新
      this.client.on('Disconnect', () => {
        this.connected = false;
        if (this.events.onClose) {
          this.events.onClose();
        }
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      throw new SSHConnectionError(`Failed to start shell: ${message}`);
    }
  }

  /**
   * シェルにデータを書き込む
   */
  async write(data: string): Promise<void> {
    if (!this.connected || !this.client) {
      throw new SSHConnectionError('Not connected');
    }

    try {
      await this.client.writeToShell(data);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      throw new SSHConnectionError(`Failed to write: ${message}`);
    }
  }

  /**
   * ターミナルサイズを変更する
   */
  async resize(cols: number, rows: number): Promise<void> {
    if (!this.connected || !this.client) {
      throw new SSHConnectionError('Not connected');
    }

    try {
      await this.client.resizeShell(cols, rows);
    } catch (error) {
      // リサイズエラーは警告のみ（致命的ではない）
      console.warn('Failed to resize terminal:', error);
    }
  }

  /**
   * コマンドを実行して結果を取得する
   */
  async exec(command: string): Promise<string> {
    if (!this.connected || !this.client) {
      throw new SSHConnectionError('Not connected');
    }

    try {
      const result = await this.client.execute(command);
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      throw new SSHConnectionError(`Failed to execute command: ${message}`);
    }
  }

  /**
   * イベントハンドラを設定する
   */
  setEventHandlers(events: Partial<SSHEvents>): void {
    this.events = { ...this.events, ...events };
  }
}

/**
 * SSHクライアントファクトリ
 */
export function createSSHClient(): ISSHClient {
  return new SSHClient();
}
