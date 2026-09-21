const colors = require('tailwindcss/colors')

// SWARM change: the Zcash palette is replaced by the Swarm Style Guide v2
// tokens. Colour has meaning here and the names say what it is:
//
//   hive     #FF8A1F  brand, primary action, SHIELDED state, value
//   honey    #FFB020  highlights, mining rewards, COINBASE
//   honeyLt  #FFD08A  text on honey-tinted surfaces
//   clear    #6FB6FF  ONLY transparent / REVEALED data
//   success  #3DD68C  confirmations
//
// Do not reach for clear-blue as a neutral accent: on this explorer blue means
// "this data is public", and using it decoratively would lie to the reader.
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
        sw: {
          void: '#0A0908',
          base: '#100E0C',
          s1: '#171411',
          s2: '#1F1B17',
          text: '#F5EFE4',
          text2: '#D9D1C4',
          mid: '#A89F92',
          dim: '#7D746A',
          low: '#6B645A',
          hive: '#FF8A1F',
          honey: '#FFB020',
          honeyLt: '#FFD08A',
          clear: '#6FB6FF',
          clearLt: '#BFDDFF',
          success: '#3DD68C',
          danger: '#FF5C5C'
        }
      },
      fontFamily: {
        display: ['Sora', 'system-ui', 'sans-serif'],
        sans: ['Manrope', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'ui-monospace', 'monospace']
      },
      borderRadius: {
        flat: '10px',
        surface: '14px',
        raised: '16px',
        glow: '18px'
      }
    }
  },
  plugins: [require('@tailwindcss/forms')]
}
