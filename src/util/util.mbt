///| Extract content between XML-style tags.

///|

///| Searches for `<tag_name>...</tag_name>` and returns the content between them.

///| The close tag search starts from after the open tag, preventing cross-tag

///| mismatches when close tag text appears before the open tag.

///|
/// Returns None if either the open tag or the close tag is not found.
pub fn extract_tag_content(text : String, tag_name : String) -> String? {
  let open_tag = "<\{tag_name}>"
  let close_tag = "</\{tag_name}>"
  let open_idx = text.find(open_tag)
  match open_idx {
    Some(start) => {
      let content_start = start + open_tag.length()
      // Search for close tag only in the text after the open tag
      let remaining = text.view(start_offset=content_start).to_string()
      let close_idx = remaining.find(close_tag)
      match close_idx {
        Some(rel_end) =>
          Some(
            text
            .view(
              start_offset=content_start,
              end_offset=content_start + rel_end,
            )
            .to_string(),
          )
        None => None
      }
    }
    None => None
  }
}
