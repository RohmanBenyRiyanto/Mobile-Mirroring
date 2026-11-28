/* Settings you may want to change. © 2026 Rohman Beny Riyanto */
window.BENZ_CONFIG = {
  owner: 'RohmanBenyRiyanto',
  repo: 'Mobile-Mirroring',

  /* Preferred DMG name; a release with a versioned name such as Benz-Mirror-0.1.0-beta.1.dmg falls back to its first DMG. */
  assetName: 'Benz-Mirror.dmg',

  /* Second source, for DMG files committed to the repository instead of a GitHub Release.
     File name pattern: Benz-Mirror-0.1.0.dmg, with an optional Benz-Mirror-0.1.0.dmg.sha256 beside it. */
  folder: { branch: 'release/production', path: 'releases' },

  /* Where CHANGELOG.md is read from. */
  changelog: { branch: 'release/production', path: 'CHANGELOG.md' }
};
