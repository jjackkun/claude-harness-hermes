// [예시] ESLint no-restricted-imports — 디렉토리 경계 강제 (R1 패턴).
//
// ⚠️ 이 파일은 ai-dev-setting 의 *예시 갤러리* 에 있다.
//    rim-kanban 의 eslint.config.js 에서 4개 블록 발췌.
//
// 왜 pytest 예시(test_mode_isolation.py)와 *중복*으로 이것도 필요한가:
//   - Python 쪽은 backend 를 지키고 ESLint 는 frontend(SvelteKit src/lib) 를 지킨다.
//   - 한 언어에만 강제가 있으면 다른 언어에서 새어나간다.
//   - PDF 9쪽 "맞춤형 린트" 의 TypeScript 응용.
//
// 치환 대상:
//   - "kanban/once" 등 경로 패턴 → 자기 프로젝트 feature 디렉토리
//   - 에러 메시지의 "R1 위반: ..." → 자기 룰 번호와 도메인 언어
//   - 모드 이름(once/scheduled/realtime) → 자기 격리 대상 이름들
//
// 주의: 아래는 eslint.config.js (flat config) 의 *일부 블록* 이다.
//       `defineConfig([...])` 배열에 병합해서 쓸 것.

export default [
  // R1 불변: 실행 모드 3개는 서로 import 금지. 공통 로직은 shared/ 경유.
  {
    files: ['src/lib/features/kanban/once/**'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: [
                '**/kanban/scheduled/**',
                '**/kanban/realtime/**',
                '**/scheduled/**',
                '**/realtime/**',
                '../scheduled',
                '../scheduled/*',
                '../realtime',
                '../realtime/*'
              ],
              message:
                'R1 위반: once/ 는 scheduled/ 또는 realtime/ 을 import 할 수 없다. shared/ 를 경유하라.'
            }
          ]
        }
      ]
    }
  },
  {
    files: ['src/lib/features/kanban/scheduled/**'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: [
                '**/kanban/once/**',
                '**/kanban/realtime/**',
                '**/once/**',
                '**/realtime/**',
                '../once',
                '../once/*',
                '../realtime',
                '../realtime/*'
              ],
              message:
                'R1 위반: scheduled/ 는 once/ 또는 realtime/ 을 import 할 수 없다. shared/ 를 경유하라.'
            }
          ]
        }
      ]
    }
  },
  {
    files: ['src/lib/features/kanban/realtime/**'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: [
                '**/kanban/once/**',
                '**/kanban/scheduled/**',
                '**/once/**',
                '**/scheduled/**',
                '../once',
                '../once/*',
                '../scheduled',
                '../scheduled/*'
              ],
              message:
                'R1 위반: realtime/ 은 once/ 또는 scheduled/ 를 import 할 수 없다. shared/ 를 경유하라.'
            }
          ]
        }
      ]
    }
  },
  // shared/ 는 의존 역전을 막기 위해 모드 전용 디렉토리를 import 할 수 없다.
  {
    files: ['src/lib/features/kanban/shared/**'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: [
                '**/kanban/once/**',
                '**/kanban/scheduled/**',
                '**/kanban/realtime/**',
                '../once',
                '../once/*',
                '../scheduled',
                '../scheduled/*',
                '../realtime',
                '../realtime/*'
              ],
              message: 'R1 위반: shared/ 는 모드 전용 디렉터리를 import 할 수 없다(의존 역전).'
            }
          ]
        }
      ]
    }
  }
];
