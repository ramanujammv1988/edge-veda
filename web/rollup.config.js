import typescript from '@rollup/plugin-typescript';
import resolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import terser from '@rollup/plugin-terser';
import json from '@rollup/plugin-json';

const production = !process.env.ROLLUP_WATCH;

const baseConfig = {
  external: [],
  plugins: [
    json(),
    resolve({
      browser: true,
      preferBuiltins: false,
    }),
    commonjs(),
    typescript({
      tsconfig: './tsconfig.json',
      sourceMap: true,
      declaration: true,
      declarationDir: './dist',
    }),
  ],
};

export default [
  // Main library bundle (ESM)
  {
    input: 'src/index.ts',
    output: {
      file: 'dist/index.js',
      format: 'es',
      sourcemap: true,
    },
    ...baseConfig,
    plugins: [
      ...baseConfig.plugins,
      production && terser({
        compress: {
          pure_getters: true,
          unsafe: true,
          unsafe_comps: true,
        },
        mangle: {
          properties: false,
        },
      }),
    ],
  },

  // Main library bundle (UMD)
  {
    input: 'src/index.ts',
    output: {
      file: 'dist/index.cjs',
      format: 'umd',
      name: 'EdgeVeda',
      sourcemap: true,
      exports: 'named',
    },
    ...baseConfig,
    plugins: [
      ...baseConfig.plugins,
      production && terser({
        compress: {
          pure_getters: true,
          unsafe: true,
          unsafe_comps: true,
        },
        mangle: {
          properties: false,
        },
      }),
    ],
  },

  // Worker bundle (ESM)
  {
    input: 'src/worker.ts',
    output: {
      file: 'dist/worker.js',
      format: 'es',
      sourcemap: true,
    },
    external: [],
    plugins: [
      json(),
      resolve({
        browser: true,
        preferBuiltins: false,
      }),
      commonjs(),
      typescript({
        tsconfig: './tsconfig.json',
        sourceMap: true,
        declaration: true,
        declarationDir: './dist',
      }),
      production && terser({
        compress: {
          pure_getters: true,
          unsafe: true,
          unsafe_comps: true,
        },
        mangle: {
          properties: false,
        },
      }),
    ],
  },

  // Minified browser bundle (UMD) with everything
  {
    input: 'src/index.ts',
    output: {
      file: 'dist/edgeveda.min.js',
      format: 'umd',
      name: 'EdgeVeda',
      sourcemap: true,
      exports: 'named',
    },
    ...baseConfig,
    plugins: [
      ...baseConfig.plugins,
      terser({
        compress: {
          pure_getters: true,
          unsafe: true,
          unsafe_comps: true,
          drop_console: true,
        },
        mangle: {
          properties: false,
        },
      }),
    ],
  },
].filter(Boolean);
