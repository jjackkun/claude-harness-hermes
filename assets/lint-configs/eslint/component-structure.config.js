// [하네스] ESLint — 컴포넌트 .vue 직접 import 금지 (R-struct-3)
//
// pre-commit 의 check-component-structure.mjs 와 동일 규칙을 ESLint 단에서도 강제한다.
// 두 층이 겹치는 이유: pre-commit 은 staged 파일만 검사하지만 ESLint 는 IDE 실시간 피드백을 제공.
//
// 설치: eslint.config.js 의 defineConfig([...]) 배열에 spread 해서 병합
//   import componentStructure from './lint-configs/harness-component-structure.config.js'
//   export default defineConfig([...componentStructure, ...yourRules])
//
// 예외: index.js/index.ts (배럴) 는 .vue 직접 import 허용.
//       components/ui/ (shadcn 생성물) 도 제외.

export default [
  {
    // 배럴(index.js/ts) 및 shadcn ui/ 제외
    files: [
      'src/**/*.vue',
      'src/**/*.ts',
      'src/**/*.tsx',
      'src/**/*.js',
      'src/**/*.jsx',
    ],
    ignores: [
      'src/**/index.js',
      'src/**/index.ts',
      'src/components/ui/**',
    ],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              // *.vue 를 파일 경로로 직접 import 하는 패턴
              group: ['**/*.vue'],
              message:
                '[R-struct-3] .vue 직접 import 금지 → 폴더명으로 import 하세요.\n' +
                '  예) \'./parts/Foo.vue\' → \'./parts/Foo\'\n' +
                '  근거: assets/rules/web/coding-style.md §File-Organization',
            },
          ],
        },
      ],
    },
  },
]
