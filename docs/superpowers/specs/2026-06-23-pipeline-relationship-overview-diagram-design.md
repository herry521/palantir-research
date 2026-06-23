# Pipeline Relationship Overview Diagram Design

## Summary

1. Add a static relationship diagram to `deliverables/pages/overview.html` between the platform map and operator sections.
2. Use HTML/CSS rather than a screenshot so the diagram stays responsive, searchable, and easy to update.
3. Present `Pipeline Builder` and `Code Repositories` as authoring surfaces, not execution engines.
4. Present `Batch`, `Incremental`, and `Streaming` as pipeline types; `Faster` is a variant of Batch/Incremental, not a standalone type.
5. Mark Code Repositories streaming support as an advanced Java/UDF-oriented path.

## Design

The overview page will get a new `page-section` titled `Pipeline 开发入口与类型关系`. The visual uses two columns:

- `Pipeline Builder`: Batch, Incremental, Streaming.
- `Code Repositories`: Batch, Incremental, Streaming with an advanced-user note.

`Faster` appears as compact chips inside Batch and Incremental cards. The section also includes three short fact cards explaining the corrections: Streaming is not a Batch child, Faster is a variant, and Code Repositories can support Streaming for advanced users.

## Files

- Modify `deliverables/pages/overview.html` to insert the section.
- Modify `deliverables/styles.css` to add the diagram layout and mobile behavior.
