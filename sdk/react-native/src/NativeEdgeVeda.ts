import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

/**
 * TurboModule spec for Edge Veda native module.
 */
export interface Spec extends TurboModule {
  initialize(config: Object): Promise<number>;
  generate(handle: number, prompt: string, options: Object): Promise<Object>;
  startStream(
    handle: number,
    prompt: string,
    options: Object
  ): Promise<number>;
  nextToken(streamHandle: number): Promise<Object | null>;
  cancelStream(streamHandle: number): void;
  transcribe(
    handle: number,
    audioPath: string,
    options: Object
  ): Promise<Object>;
  embed(handle: number, text: string): Promise<Object>;
  getMemoryUsage(handle: number): Promise<Object>;
  dispose(handle: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('EdgeVeda');
