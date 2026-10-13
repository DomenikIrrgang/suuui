# Fonts

Both families are licensed under the SIL Open Font License 1.1. Each licence text sits beside its font files.

| File | Source | Changes |
|---|---|---|
| `MarcellusSC-Regular.ttf` | Google Fonts (`google/fonts`, `ofl/marcellussc`) | None. "Marcellus" is a Reserved Font Name, so this file must stay unmodified |
| `Figtree-Regular.ttf`, `-Medium`, `-SemiBold`, `-Bold` | Figtree's upstream static TTFs (`erikdkennedy/figtree`, `fonts/ttf`), which are the source of the Google Fonts release | None |
| `FigtreeTabular-Bold.ttf` | Built from `Figtree-Bold.ttf` by `tools/make_tabular_font.py` | The digits 0–9 map to Figtree's own tabular figures, and the family is renamed "Figtree Tabular". WoW applies no OpenType features, so this is how the `numeric` and `micro` styles get tabular figures. Figtree has no Reserved Font Name |
