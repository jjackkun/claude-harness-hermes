# harness-eval 시험이 같은 픽스처 설치를 9번 한다

발견: 2026-11-25 slow-spot 스킬 첫 적용(`completed/2026-11-25-slow-spot-skill.md` §8).

- `tests/harness-eval-test.sh` 추적 없이 83.2초(2026-11-25, 단독 실행). 프로파일: 시험 안 함수 `R`(러너 호출) 87.8%.
- `R` 이 부르는 `scripts/harness-eval.py` 는 부를 때마다 `_build_template` 에서 `project-claude.sh <tpl> harness hermes`
  를 새로 돈다(설치 1회 약 8초). 시험 하나에 러너 호출 9번 → 같은 설치 9번.
- 후보: 러너에 이미 만든 템플릿 폴더를 받는 선택 인자(예 `--template-dir`)를 두고, 시험은 첫 호출의 템플릿을 재사용한다.
  기대 절감 약 60초(8초 × 8번). 실제 평가(모델 호출)에는 영향 없음 — 시험 전용 경로.
- 지킬 것: 템플릿 재사용이 판 사이 상태를 새게 하지 않는지 — 러너는 판마다 `copytree` 하므로 원본 템플릿은 읽기만 한다(확인 필요).
  slow-spot ③대로 재사용 전후 러너 출력 JSON(집계 필드)을 대조한다.
