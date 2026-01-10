/**
 * Type declarations for react-native-ssh-sftp
 *
 * This library doesn't provide TypeScript types, so we declare them here.
 */
declare module 'react-native-ssh-sftp' {
  export interface SSHClientConfig {
    host: string;
    port: number;
    username: string;
    password?: string;
    privateKey?: string;
    passphrase?: string;
  }

  export interface ShellConfig {
    ptyWidth?: number;
    ptyHeight?: number;
  }

  export interface SSHClientInstance {
    startShell(term: string, config?: ShellConfig): Promise<void>;
    writeToShell(data: string): Promise<void>;
    resizeShell(cols: number, rows: number): Promise<void>;
    execute(command: string): Promise<string>;
    disconnect(): Promise<void>;
    on(event: 'Shell' | 'Disconnect', callback: (data?: string) => void): void;
  }

  const SSHClient: {
    connectWithPassword(
      host: string,
      port: number,
      username: string,
      password: string
    ): Promise<SSHClientInstance>;

    connectWithKey(
      host: string,
      port: number,
      username: string,
      privateKey: string,
      passphrase?: string
    ): Promise<SSHClientInstance>;
  };

  export default SSHClient;
}
