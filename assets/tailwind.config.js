const colors = require('tailwindcss/colors')
const defaultTheme = require('tailwindcss/defaultTheme')

// SWARM change: the Zcash palette is replaced by the swarm.green design tokens
// (css/site.css on the live site). Names match the tokens there so the explorer
// and the website stay in step.
module.exports = {
  darkMode: 'class',
  content: [
    '../lib/**/*.ex',
    '../lib/**/*.leex',
    '../lib/**/*.heex',
    '../lib/**/*.eex',
    './js/**/*.js'
  ],
  theme: {
    extend: {
      colors: {
        green: colors.emerald,
        yellow: colors.amber,
        purple: colors.violet,
        swarm: {
          honey:       '#F5A623',  // --honey
          amber:       '#E8890C',  // --amber-deep
          comb:        '#FFC94D',  // --comb
          pollen:      '#FFE9A8',  // --pollen
          cream:       '#FFF8E7',  // --cream
          hive:        '#0E1116',  // --hive-black
          bark:        '#161A21',  // --bark
          wax:         '#252A33',  // --wax
          ink:         '#E6EDF3',  // --ink
          'ink-dim':   '#9AA4B2',  // --ink-dim
          leaf:        '#3FB950',  // --leaf
          // The only amber that clears WCAG AA as text on --cream (6.4:1).
          'honey-ink': '#8A4B03',  // --honey-ink
        },
      },
      fontFamily: {
        // swarm.green stacks. Inter is self-hosted via @fontsource; Sora and
        // JetBrains Mono fall back to system faces rather than pulling a
        // third-party font file at page load.
        sans:    ['Inter var', 'Inter', ...defaultTheme.fontFamily.sans],
        display: ['Sora', 'Segoe UI Variable Display', 'Segoe UI', ...defaultTheme.fontFamily.sans],
        mono:    ['JetBrains Mono', 'ui-monospace', 'Cascadia Mono', ...defaultTheme.fontFamily.mono],
      },
    },
  },
  plugins: [require('@tailwindcss/forms')],
}
