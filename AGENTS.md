# Agent instructions

- Keep documentation synchronized with substantive code, script, directory, or
  workflow changes in the same commit.
- Do not commit package archives, generated repodata, build directories, or
  tool caches.
- The seed is defined by `seed-packages.tsv`; update that manifest deliberately
  when changing the seed.
- For commits produced with LLM assistance, include this trailer in the commit
  message:

  ```text
  Assisted-by: LLM
  ```
