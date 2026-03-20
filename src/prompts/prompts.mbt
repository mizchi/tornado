pub fn code_quality_checklist(lang : String) -> String {
  let buf = StringBuilder::new()
  if lang == "ja" {
    buf.write_string("## レビュー観点: コード品質\n")
    buf.write_string("以下の観点で評価してください:\n")
    buf.write_string("- 可読性と命名規約\n")
    buf.write_string("- 関心の分離\n")
    buf.write_string("- エラーハンドリングの網羅性\n")
    buf.write_string("- テストカバレッジと正確性\n")
    buf.write_string("- コードの重複と不必要な複雑さ\n")
    buf.write_string("- API 設計と公開インターフェースの明確さ\n")
  } else {
    buf.write_string("## Review Focus: Code Quality\n")
    buf.write_string("Evaluate the following aspects:\n")
    buf.write_string("- Readability and naming conventions\n")
    buf.write_string("- Proper separation of concerns\n")
    buf.write_string("- Error handling completeness\n")
    buf.write_string("- Test coverage and correctness\n")
    buf.write_string("- Code duplication and unnecessary complexity\n")
    buf.write_string("- API design and public interface clarity\n")
  }
  buf.to_string()
}

pub fn performance_checklist(lang : String) -> String {
  let buf = StringBuilder::new()
  if lang == "ja" {
    buf.write_string("## レビュー観点: パフォーマンス\n")
    buf.write_string("以下の観点で評価してください:\n")
    buf.write_string("- アルゴリズムの計算量（時間・空間）\n")
    buf.write_string("- 不要なメモリ確保やコピー\n")
    buf.write_string("- N+1 クエリや冗長な I/O\n")
    buf.write_string("- キャッシュの活用機会\n")
    buf.write_string("- ホットパスの最適化\n")
  } else {
    buf.write_string("## Review Focus: Performance\n")
    buf.write_string("Evaluate the following aspects:\n")
    buf.write_string("- Algorithmic complexity (time and space)\n")
    buf.write_string("- Unnecessary allocations or copies\n")
    buf.write_string("- N+1 queries or redundant I/O\n")
    buf.write_string("- Caching opportunities\n")
    buf.write_string("- Hot path optimization\n")
  }
  buf.to_string()
}

pub fn security_checklist(lang : String) -> String {
  let buf = StringBuilder::new()
  if lang == "ja" {
    buf.write_string("## レビュー観点: セキュリティ\n")
    buf.write_string("以下の観点で評価してください:\n")
    buf.write_string("- 入力値のバリデーションとサニタイズ\n")
    buf.write_string("- インジェクション脆弱性（コマンド、SQL、XSS）\n")
    buf.write_string("- 認証・認可の不備\n")
    buf.write_string("- 機密データの露出（シークレット、トークン、個人情報）\n")
    buf.write_string("- 依存関係の安全性\n")
  } else {
    buf.write_string("## Review Focus: Security\n")
    buf.write_string("Evaluate the following aspects:\n")
    buf.write_string("- Input validation and sanitization\n")
    buf.write_string("- Injection vulnerabilities (command, SQL, XSS)\n")
    buf.write_string("- Authentication and authorization gaps\n")
    buf.write_string("- Sensitive data exposure (secrets, tokens, PII)\n")
    buf.write_string("- Dependency safety\n")
  }
  buf.to_string()
}
