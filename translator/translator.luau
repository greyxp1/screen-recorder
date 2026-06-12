-- Translator launcher provider.
--
-- Usage from the launcher: `/tr <lang> <text>` — e.g. `/tr es hello world`.
-- If the first word is not a language, the whole query is translated to the
-- configured default target. Press Enter on a result to copy it to the clipboard.
-- Translation uses Google Translate's public `translate_a/single` endpoint.

local DEFAULT_TARGET = noctalia.getConfig("target_lang")
if type(DEFAULT_TARGET) ~= "string" or DEFAULT_TARGET == "" then
  DEFAULT_TARGET = "en"
end

-- Common language aliases → ISO code. Any other 2–3 letter token is passed
-- through to Google as-is, so uncommon languages still work.
local LANGUAGES = {
  ar = { "arabic", "arabe" },
  cs = { "czech", "tcheque" },
  de = { "german", "allemand", "deutsch" },
  el = { "greek", "grec" },
  en = { "english", "anglais" },
  es = { "spanish", "espagnol", "espanol" },
  fa = { "persian", "farsi", "persan" },
  fi = { "finnish", "finnois" },
  fr = { "french", "francais" },
  he = { "hebrew", "hebreu" },
  hi = { "hindi" },
  hu = { "hungarian", "hongrois" },
  id = { "indonesian", "indonesien" },
  it = { "italian", "italien" },
  ja = { "japanese", "japonais" },
  ko = { "korean", "coreen" },
  nl = { "dutch", "neerlandais" },
  no = { "norwegian", "norvegien" },
  pl = { "polish", "polonais" },
  pt = { "portuguese", "portugais" },
  ro = { "romanian", "roumain" },
  ru = { "russian", "russe" },
  sv = { "swedish", "suedois" },
  tr = { "turkish", "turc" },
  uk = { "ukrainian", "ukrainien" },
  vi = { "vietnamese", "vietnamien" },
  zh = { "chinese", "chinois", "mandarin" },
}

local ALIAS_TO_CODE = {}
for code, aliases in LANGUAGES do
  ALIAS_TO_CODE[code] = code
  for _, alias in aliases do
    ALIAS_TO_CODE[alias] = code
  end
end

-- target|text -> translation; pending guards against duplicate in-flight fetches.
local cache = {}
local pending = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function urlEncode(s)
  return (s:gsub("[^%w%-_%.~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- Resolve a token to a language code: a known alias, or a bare 2–3 letter code.
local function resolveLang(token)
  local lower = token:lower()
  if ALIAS_TO_CODE[lower] then
    return ALIAS_TO_CODE[lower]
  end
  if lower:match("^%a%a%a?$") then
    return lower
  end
  return nil
end

-- Google returns [[[ "segment", "orig", ... ], ...], ...]; the translation is the
-- concatenation of segment[1] across the first array.
local function parseGoogle(body)
  local decoded = noctalia.json.decode(body)
  if type(decoded) ~= "table" or type(decoded[1]) ~= "table" then
    return nil
  end
  local parts = {}
  for _, segment in decoded[1] do
    if type(segment) == "table" and type(segment[1]) == "string" then
      parts[#parts + 1] = segment[1]
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts)
end

local function fetchGoogle(text, target, onDone)
  local url = "https://translate.google.com/translate_a/single?client=gtx&sl=auto&tl="
    .. urlEncode(target)
    .. "&dt=t&q="
    .. urlEncode(text)
  noctalia.http({ url = url }, function(res)
    if not res.ok then
      onDone(nil, "Connection error — is the network up?")
      return
    end
    local translated = parseGoogle(res.body)
    if translated then
      onDone(translated, nil)
    else
      onDone(nil, "Translation error")
    end
  end)
end

local function hintRow(title, subtitle, glyph)
  return { id = title, title = title, subtitle = subtitle, glyph = glyph }
end

local function resultRow(translated, target)
  return {
    id = translated,
    title = translated,
    subtitle = "Translation (" .. target .. ") — press Enter to copy",
    glyph = "language",
  }
end

function onQuery(query)
  local text = trim(query:gsub("%s+", " "))
  if text == "" then
    launcher.setResults(query, { hintRow("Translate text", "Type: <lang> <text> — e.g. es hello", "language") })
    return
  end

  local first, rest = text:match("^(%S+)%s+(.*)$")
  local target, content
  if first then
    local code = resolveLang(first)
    if code then
      target = code
      content = trim(rest)
    else
      target = DEFAULT_TARGET
      content = text
    end
  else
    if resolveLang(text) then
      launcher.setResults(query, { hintRow("Type text to translate", "Target language: " .. text, "language") })
      return
    end
    target = DEFAULT_TARGET
    content = text
  end

  if content == "" then
    launcher.setResults(query, { hintRow("Type text to translate", "Target language: " .. target, "language") })
    return
  end

  local key = target .. "|" .. content
  local cached = cache[key]
  if cached then
    launcher.setResults(query, { resultRow(cached, target) })
    return
  end

  launcher.setResults(query, { hintRow("Translating…", content, "loader") })
  if not pending[key] then
    pending[key] = true
    fetchGoogle(content, target, function(translated, err)
      pending[key] = nil
      if translated then
        cache[key] = translated
        launcher.setResults(query, { resultRow(translated, target) })
      else
        launcher.setResults(query, { hintRow(err or "Translation error", content, "alert-triangle") })
      end
    end)
  end
end

function onActivate(id)
  if id ~= "" then
    noctalia.copyToClipboard(id, "text/plain")
    noctalia.notify("Translator", "Copied to clipboard")
  end
end
