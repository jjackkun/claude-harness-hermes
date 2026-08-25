// ai-dev-setting/assets/lint-configs/eslint/max-lines.config.js
//
// PDF 9쪽 인용:
//   "맞춤형 린터를 사용하여 구조화된 로깅, 스키마 및 유형의 명명 규칙,
//    파일 크기 제한, 플랫폼별 안정성 요구 사항을 정적으로 적용합니다.
//    린트가 맞춤형이므로 오류 메시지를 작성하여 에이전트 컨텍스트에
//    수정 지침을 주입합니다."
//
// 본 설정은 ESLint 의 표준 max-lines 룰을 그대로 쓰지만, project-claude.sh 가
// 이 파일을 프로젝트 eslint.config.js 에 머지할 때 한국어 수정 지침을 함께
// 주석으로 박아둔다 (해당 ESLint 버전에서 message override 가 안 되는 경우의
// fallback). max-lines 룰 자체는 메시지를 영어 고정으로 출력하므로,
// 위반 발생 시 본 파일 상단의 "에이전트 자가 판단 가이드" 가 컨텍스트에서
// 보조 역할을 한다.
//
// 두 층 한도 (rim-kanban Phase 1 패턴):
//   - 본 ESLint 한도: SOFT (작성 직후 권장)
//   - .git/hooks/pre-commit 의 MAX_LINES_HARD: HARD (절대, 우회 불가)
//   값이 다른 게 의도다. SOFT 가 먼저 울려 에이전트가 자가 교정할 시간을 준다.
//
// 한도 조정: .harnessrc 또는 환경변수 HARNESS_MAX_LINES_SOFT 로 override.

/**
 * 【에이전트 자가 판단 가이드 — max-lines 위반 시】
 *
 * ESLint 가 "File has too many lines" 를 띄웠을 때 다음 절차를 따른다:
 *
 * 1. 이 파일이 단일 책임을 지키고 있는가?
 *    - YES → 2번
 *    - NO  → 책임별 분리. 예: 데이터 조회 / 검증 / 응답 직렬화 분리.
 *
 * 2. 헬퍼 함수들을 별도 모듈로 추출 가능한가?
 *    - YES → 같은 디렉터리의 _helpers.* 또는 utils/ 로 이동.
 *    - NO  → 3번
 *
 * 3. 한도가 정말 잘못 잡혔다는 *증거*가 있는가?
 *    - 있다면: docs/audits/YYYY-MM-DD-size-limit-review.md 에 근거 기록 후
 *             .harnessrc 의 HARNESS_MAX_LINES_SOFT 를 조정.
 *    - 없다면: 1·2 반복. 한도 조정은 마지막 선택지.
 *
 * PDF 근거: 9쪽 "파일 크기 제한... 정적으로 적용"
 */

const HARNESS_MAX_LINES_SOFT = parseInt(process.env.HARNESS_MAX_LINES_SOFT || '400', 10);

export default {
	rules: {
		'max-lines': [
			'error',
			{
				max: HARNESS_MAX_LINES_SOFT,
				skipBlankLines: true,
				skipComments: true
			}
		]
	}
};
