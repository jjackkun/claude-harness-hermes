export type RosterView = { isOk: boolean; lines: string[] }

declare module 'claude-code' {
  interface PluginState {
    'hermes-roster-pane': { view: RosterView | null }
  }
}
