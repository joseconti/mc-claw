# Phase 2: Implementation

## Tool Implementation
- Input Schema: Use Zod (TypeScript) or Pydantic (Python)
- Output Schema: Define outputSchema where possible
- Annotations: readOnlyHint, destructiveHint, idempotentHint, openWorldHint

## Error Handling
- Consistent error format across all tools
- Clear error messages for API failures
- Graceful degradation

## Review Checklist
- No duplicated code (DRY)
- Consistent error handling
- Full type coverage
- Test with MCP Inspector
