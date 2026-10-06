import Prism from './vendor/prism.js'

// vue 템플릿의 바인딩 속성 이름: :class, @click.prevent, #default, v-if, v-model …
const VUE_BINDING = String.raw`(?:[:@#]|v-)[^\s=>/]+`
type TagWithHelpers = { addAttribute: (namePattern: string, language: string) => void }

let isRegistered = false

// 묶음에 없는 문법 두 개를 한 번만 더한다.
//  - markup-plain: vue 규칙을 더하기 전의 마크업 그대로(html·svelte·xml 용)
//  - vue: 마크업 + 바인딩 속성의 값과 {{ }} 안을 JS 로
export const registerGrammars = (): void => {
  if (isRegistered) {
    return
  }
  isRegistered = true
  const { languages } = Prism
  // 아래 두 줄이 마크업 문법을 고치므로, 그 전에 통째로 복제해 둔다.
  languages['markup-plain'] = Prism.util.clone(languages['markup'])
  ;(languages['markup']?.['tag'] as TagWithHelpers).addAttribute(VUE_BINDING, 'javascript')
  languages['vue'] = languages.insertBefore('markup', 'tag', {
    interpolation: {
      pattern: /\{\{[\s\S]*?\}\}/,
      inside: {
        punctuation: /^\{\{|\}\}$/,
        'language-javascript': { pattern: /[\s\S]+/, inside: languages['javascript'] },
      },
    },
  })
}
