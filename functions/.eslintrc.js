module.exports = {
  root: true,
  env: { node: true, es2020: true },
  parser: "@typescript-eslint/parser",
  plugins: ["@typescript-eslint"],
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended"
  ],
  ignorePatterns: ["lib/**", "generated/**"],
  rules: {
    "@typescript-eslint/no-explicit-any": "off",
    "@typescript-eslint/no-unused-vars": "off",
    "no-unused-vars": "off",
    "quotes": ["error", "double"],
    "indent": ["error", 2]
    }
};
