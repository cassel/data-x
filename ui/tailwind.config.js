/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'dark-bg': '#1a1a2e',
        'dark-panel': '#16213e',
        'dark-accent': '#0f3460',
        'accent': '#e94560',
        'accent-light': '#ff6b6b',
      },
    },
  },
  plugins: [],
}
