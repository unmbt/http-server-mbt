///|
/// Escape characters for safe HTML rendering.
pub fn escape_html(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    match c {
      '&' => buf.write_string("&#x26;")
      '<' => buf.write_string("&#x3C;")
      '>' => buf.write_string("&#x3E;")
      '"' => buf.write_string("&#x22;")
      '\'' => buf.write_string("&#x27;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn encode_path_segment(s : String) -> String {
  let bytes = @utf8.encode(s)
  let buf = StringBuilder()
  for b in bytes {
    let cp = b.to_int()
    if (cp >= 'A'.to_int() && cp <= 'Z'.to_int()) ||
      (cp >= 'a'.to_int() && cp <= 'z'.to_int()) ||
      (cp >= '0'.to_int() && cp <= '9'.to_int()) ||
      cp == '-'.to_int() ||
      cp == '_'.to_int() ||
      cp == '.'.to_int() ||
      cp == '~'.to_int() {
      buf.write_char(Int32::unsafe_to_char(cp))
    } else {
      let hex = "0123456789ABCDEF"
      buf.write_char('%')
      buf.write_char(hex[(cp >> 4) & 0xF].to_int().unsafe_to_char())
      buf.write_char(hex[cp & 0xF].to_int().unsafe_to_char())
    }
  }
  buf.to_string()
}

///|

///|

///|
fn format_file_size(size : Int64) -> String {
  if size < 1024L {
    size.to_string() + "B"
  } else if size < 1048576L {
    let kb = size.to_double() / 1024.0
    format_1dec(kb) + "k"
  } else if size < 1073741824L {
    let mb = size.to_double() / 1048576.0
    format_1dec(mb) + "M"
  } else {
    let gb = size.to_double() / 1073741824.0
    format_1dec(gb) + "G"
  }
}

///|
fn format_1dec(val : Double) -> String {
  let rounded = (val * 10.0 + 0.5).to_int64()
  let whole = rounded / 10L
  let frac = rounded % 10L
  whole.to_string() + "." + frac.to_string()
}

///|
fn format_listing_timestamp(epoch_sec : Int64) -> String {
  let days_since_epoch = (epoch_sec / 86400L).to_int()
  let mut rem_sec = (epoch_sec % 86400L).to_int()
  if rem_sec < 0 {
    rem_sec = rem_sec + 86400
  }
  let hour = rem_sec / 3600
  let minute = rem_sec % 3600 / 60

  let months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  let mut y = 1970
  let mut d = days_since_epoch
  if d >= 0 {
    while true {
      let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      let days_in_year = if leap { 366 } else { 365 }
      if d < days_in_year {
        break
      }
      d = d - days_in_year
      y = y + 1
    }
  } else {
    while d < 0 {
      y = y - 1
      let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      let days_in_year = if leap { 366 } else { 365 }
      d = d + days_in_year
    }
  }
  let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
  let month_days = if leap {
    [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  } else {
    [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  }
  let mut m = 0
  while m < 12 {
    if d < month_days[m] {
      break
    }
    d = d - month_days[m]
    m = m + 1
  }
  let day = d + 1
  let pad_day = if day < 10 { "0" + day.to_string() } else { day.to_string() }
  let pad_hour = if hour < 10 {
    "0" + hour.to_string()
  } else {
    hour.to_string()
  }
  let pad_min = if minute < 10 {
    "0" + minute.to_string()
  } else {
    minute.to_string()
  }
  "\{pad_day}-\{months[m]}-\{y} \{pad_hour}:\{pad_min}"
}

///|
pub(all) struct ListingEntry {
  name : String
  is_dir : Bool
  size : Int64
  mtime_sec : Int64
  mut is_companion : Bool
  mut has_br : Bool
  mut has_gz : Bool
}

///|
pub fn compare_entries(a : ListingEntry, b : ListingEntry) -> Int32 {
  let cmp = a.name.to_lower().compare(b.name.to_lower())
  if cmp != 0 {
    cmp
  } else {
    a.name.compare(b.name)
  }
}

///|
pub fn listing_header(title_path : String, _raw_query : String?) -> String {
  let buf = StringBuilder()
  let enc_title = escape_html(title_path)

  buf.write_string("<!doctype html>\n<html>\n<head>\n")
  buf.write_string("  <meta charset=\"utf-8\">\n")
  buf.write_string(
    "  <meta name=\"viewport\" content=\"width=device-width\">\n",
  )
  buf.write_string("  <title>Index of " + enc_title + "</title>\n")
  buf.write_string("  <style type=\"text/css\">\n")
  buf.write_string(
    "    body { font-family: sans-serif; margin: 2rem; }\n" +
    "    table { border-collapse: collapse; width: 100%; max-width: 960px; }\n" +
    "    td { padding: 4px 10px; }\n" +
    "    td.file-size { text-align: right; font-family: monospace; }\n" +
    "    td.last-modified { color: #666; font-size: 0.9em; }\n",
  )
  buf.write_string("  </style>\n</head>\n<body>\n")
  buf.write_string("<h1>Index of " + enc_title + "</h1>\n")
  buf.write_string("<table>\n")

  buf.to_string()
}

///|
pub fn listing_row(entry : ListingEntry, raw_query : String?) -> String {
  let buf = StringBuilder()
  let q_suffix = match raw_query {
    Some(q) if q.length() > 0 => "?" + escape_html(q)
    _ => ""
  }
  if entry.is_companion {
    return buf.to_string()
  }
  if entry.name == ".." {
    buf.write_string("<tr>")
    buf.write_string("<td class=\"last-modified\"></td>")
    buf.write_string("<td class=\"file-size\"></td>")
    buf.write_string(
      "<td class=\"display-name\"><a href=\"../" + q_suffix + "\">../</a></td>",
    )
    buf.write_string("</tr>\n")
    return buf.to_string()
  }
  let encoded_name = encode_path_segment(entry.name)
  let href = if entry.is_dir {
    "./" + encoded_name + "/" + q_suffix
  } else {
    "./" + encoded_name
  }
  let display_name = escape_html(entry.name) +
    (if entry.is_dir { "/" } else { "" })
  let size_str = if entry.is_dir { "" } else { format_file_size(entry.size) }
  let time_str = format_listing_timestamp(entry.mtime_sec)

  buf.write_string("<tr>")
  buf.write_string("<td class=\"last-modified\">" + time_str + "</td>")
  buf.write_string("<td class=\"file-size\"><code>" + size_str + "</code></td>")
  buf.write_string(
    "<td class=\"display-name\"><a href=\"" +
    href +
    "\">" +
    display_name +
    "</a>",
  )
  if entry.has_br {
    buf.write_string(
      " <span class=\"badge\"><a href=\"./" +
      encoded_name +
      ".br\">[br]</a></span>",
    )
  }
  if entry.has_gz {
    buf.write_string(
      " <span class=\"badge\"><a href=\"./" +
      encoded_name +
      ".gz\">[gz]</a></span>",
    )
  }
  buf.write_string("</td></tr>\n")

  buf.to_string()
}

///|
pub fn listing_footer(host : String) -> String {
  let buf = StringBuilder()
  buf.write_string("</table>\n")
  buf.write_string(
    "<br><address>http-server running @ " + escape_html(host) + "</address>\n",
  )
  buf.write_string("</body></html>")
  buf.to_string()
}

///|
fn render_directory_html(
  title_path : String,
  entries : Array[ListingEntry],
  raw_query : String?,
  host : String,
) -> String {
  let buf = StringBuilder()
  buf.write_string(listing_header(title_path, raw_query))
  for entry in entries {
    buf.write_string(listing_row(entry, raw_query))
  }
  buf.write_string(listing_footer(host))
  buf.to_string()
}

///|
/// Pure HTML directory listing renderer for testing and embedding (AD-05).
pub fn render_directory_listing_html(
  title_path : String,
  entry_names : Array[(String, Bool)],
  raw_query? : String?,
  host~ : String = "localhost",
) -> String {
  let entries : Array[ListingEntry] = []
  for item in entry_names {
    let (name, is_dir) = item
    entries.push({
      name,
      is_dir,
      size: 0L,
      mtime_sec: 0L,
      is_companion: false,
      has_br: false,
      has_gz: false,
    })
  }
  let q = match raw_query {
    Some(opt) => opt
    None => None
  }
  render_directory_html(title_path, entries, q, host)
}
