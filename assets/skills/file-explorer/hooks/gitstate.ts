import type { ProcessRunResult } from 'claude-code'

import type { Model } from '../types'
import { isDiffFailure, parseStatus } from './git'
import type { GitFile } from './git'
import type { Change } from './reducers'

// git 탭의 상태 계산. 엔진($)을 만지지 않는다.

export const tabbed =
  (tab: Model['tab']): Change =>
  () => ({ tab, notice: null })

// `git status` 결과를 목록으로. 다시 읽으면 고른 파일과 변경 내용은 비운다(낡은 내용을 보이지 않게).
// isQuiet: 트리 색을 위해 뒤에서 읽는 경우. 알림 줄을 건드리지 않는다(git 저장소가 아닌 폴더에서 조용히 넘어간다).
export const fromStatusRun =
  ({ exitCode, stdout, stderr }: ProcessRunResult, isQuiet = false): Change =>
  () => {
    const git = exitCode === 0 ? { ...parseStatus(stdout), listTop: 0, path: null, diff: '', top: 0 } : null
    if (isQuiet) {
      return { git }
    }

    return { git, notice: git === null ? `git 상태를 읽지 못했습니다: ${stderr.trim()}` : null }
  }

// `git diff` 결과를 고른 파일의 변경 내용으로.
export const fromDiffRun =
  (file: GitFile, { exitCode, stdout, stderr }: ProcessRunResult): Change =>
  m => {
    if (m.git === null) {
      return {}
    }

    return isDiffFailure(exitCode)
      ? { notice: `변경 내용을 읽지 못했습니다: ${stderr.trim()}` }
      : { git: { ...m.git, path: file.path, diff: stdout, top: 0 }, notice: null }
  }
