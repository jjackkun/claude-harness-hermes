import type { Elements } from 'claude-code'

import type { Model } from '../types'
import type { Window } from './view'

type Ui = Elements['terminal']
export type Tab = Model['tab']
export type Actions = {
  onTab: (tab: Tab) => void
  onRefresh: () => void
  onClose: () => void
  onCloseAll: () => void
  onToggle: () => void
  onSave: () => void
  onRevert: () => void
}

const TABS: readonly Tab[] = ['editor', 'git']

// 첫 줄: 왼쪽에 탭, 오른쪽 끝에 닫기. 지금 탭은 강조해 보인다.
const tabs = ({ Box, Button }: Ui, model: Model, actions: Actions) => (
  <Box justifyContent="space-between">
    <Box gap={1}>
      {TABS.map(tab =>
        tab === model.tab ? (
          <Button key={`tab-${tab}`} label={tab} variant="primary" onPress={() => actions.onTab(tab)} />
        ) : (
          <Button key={`tab-${tab}`} label={tab} onPress={() => actions.onTab(tab)} />
        ),
      )}
    </Box>
    <Box gap={1}>
      <Button key="close" label="닫기" role="dismiss" onPress={actions.onClose} />
      <Button key="close-all" label="전체 닫기" onPress={actions.onCloseAll} />
    </Box>
  </Box>
)

// 둘째 줄: 프로젝트 이름과 그 탭의 도구.
const tools = ({ Box, Button, Text }: Ui, model: Model, win: Window | null, actions: Actions) => {
  const { open, git } = model
  const isDirty = open !== null && open.source !== open.saved
  const title = model.project !== '' && <Text bold>{model.project}</Text>
  const refresh = <Button key="refresh" label="새로고침" hotkey="r" onPress={actions.onRefresh} />
  if (model.tab === 'git') {
    return (
      <Box gap={1}>
        {title}
        <Text>{git === null ? 'git' : `${git.branch} · 바뀐 파일 ${git.files.length}개`}</Text>
        {refresh}
      </Box>
    )
  }

  return (
    <Box gap={1}>
      {title}
      <Text>{open === null || win === null ? '파일을 고르십시오' : `${open.path} ${win.total}줄`}</Text>
      {isDirty && <Text color="warning">● 저장 안 됨</Text>}
      {isDirty && <Button key="save" label="저장" hotkey="s" variant="primary" onPress={actions.onSave} />}
      {isDirty && <Button key="revert" label="되돌리기" onPress={actions.onRevert} />}
      {open !== null && <Button key="mode" label={open.isEditing ? '보기' : '편집'} hotkey="e" onPress={actions.onToggle} />}
      {refresh}
    </Box>
  )
}

// 패널 머리 세 줄: 탭, 도구, 알림.
export const header = (ui: Ui, model: Model, win: Window | null, actions: Actions) => {
  const isEditing = model.tab === 'editor' && model.open?.isEditing === true
  const hint = isEditing ? '에디터를 눌러 커서를 놓고 입력하십시오. Esc 로 나옵니다.' : ' '

  return (
    <ui.Box flexDirection="column">
      {tabs(ui, model, actions)}
      {tools(ui, model, win, actions)}
      <ui.Text dimColor>{model.notice ?? hint}</ui.Text>
    </ui.Box>
  )
}
