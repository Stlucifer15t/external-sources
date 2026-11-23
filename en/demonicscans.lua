id       = "demonicscans"
name     = "Demonic Scans"
version  = "1.0.0"
baseUrl  = "https://demonicscans.org"
language = {"en", "es", "fr"}
content_type = "manga"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/v2/icons/demonicscans.png"

-- ── Shared libs ─────────────────────────────────────────────────────────────

local _libs
local function LIB(id)
  if type(require_lib) ~= "function" then
    show_error("Requires NoveLA update", "This plugin needs the shared libraries")
    error("Requires NoveLA update (require_lib)", 0)
  end
  if not _libs then _libs = {} end
  if not _libs[id] then _libs[id] = require_lib(id) end
  return _libs[id]
end

local function absUrl(href)
  return LIB("urls").absUrl(baseUrl, href)
end

-- Extract manga slug from /manga/{slug} URL.
local function mangaSlug(bookUrl)
  local u = tostring(bookUrl or "")
  return u:match("/manga/([^/]+)/?$") or u:match("/manga/([^/]+)") or ""
end

-- Extract manga id from chapter links on the manga page.
local function mangaId(body)
  local m = body:match("chaptered%.php%?manga=(%d+)")
  return m or ""
end

-- Extract comment thread (chapter) id from the manga page's comments widget.
local function commentChapterId(body)
  local v = html_attr(body, "#cw-comments", "data-chapter")
  if v ~= "" then return v end
  return body:match('data%-chapter="([0-9]+)"') or ""
end

-- Fetch manga page HTML (shared session cache).
local function fetchMangaPage(bookUrl)
  return LIB("fetch").page(bookUrl)
end

-- Fetch comments from the comments API, verified against a real response
-- from https://demonicscans.org/comments_api.php?chapterid=100014521&sort=newest&page=1
-- (sample: The World's Best Kunlun Tavern, 11 comments, fetched 2026-11-23).
local function fetchComments(chapterId, page)
  local url = baseUrl .. "/comments_api.php?chapterid=" .. chapterId
    .. "&sort=newest&page=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return nil end
  return json_parse(r.body)
end

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "/newmangalist.php?page=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, a in ipairs(html_select(r.body, 'a[href^="/manga/"]')) do
    local title = string_clean(a.title or a.text)
    if title ~= "" then
      table.insert(items, {
        title = title,
        url   = absUrl(a.href),
      })
    end
  end
  return { items = items, hasNext = #items > 0 }
end

-- ── Search ──────────────────────────────────────────────────────────────────

-- Demonic Scans has no working public search endpoint. Return empty so the
-- app shows "no results" rather than failing.
function getCatalogSearch(index, query)
  return { items = {}, hasNext = false }
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchMangaPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1.big-fat-titles, h1")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchMangaPage(bookUrl)
  if not body then return nil end
  local src = html_attr(body, ".manga-cover img, .cover img, .poster img", "src")
  if src == "" then
    src = html_attr(body, "img[src*='cover']", "src")
  end
  if src == "" then
    src = html_attr(body, ".manga-info img, .series-info img", "src")
  end
  return src ~= "" and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  local body = fetchMangaPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".description, .summary, .manga-description, .excerpt")
  return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
  local body = fetchMangaPage(bookUrl)
  if not body then return {} end
  return LIB("meta").collectGenres(html_select(body, ".genre a, .tag a, .manga-genre a"))
end

-- ── Rating ──────────────────────────────────────────────────────────────────

function getBookRating(bookUrl)
  local body = fetchMangaPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".rating, .score, .vote-rating")
  if el then
    local n = string.match(string_clean(el.text), "%d+%.?%d*")
    if n then return n end
  end
  return nil
end

-- ── Chapters ────────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local body = fetchMangaPage(bookUrl)
  if not body then return {} end

  local chapters = {}
  local seen = {}
  for _, a in ipairs(html_select(body, 'a[href*="chaptered.php"]')) do
    local href = a.href or ""
    local chNum = href:match("chapter=(%d+)")
    if chNum and not seen[chNum] then
      seen[chNum] = true
      local title = string_clean(a.text)
      if title == "" then title = "Chapter " .. chNum end
      table.insert(chapters, {
        title = title,
        url   = absUrl(href),
      })
    end
  end
  -- Reverse so newest chapter is last (app typically shows oldest first)
  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

function getChapterListHash(bookUrl)
  local body = fetchMangaPage(bookUrl)
  if not body then return nil end
  local count = 0
  for _ in pairs(html_select(body, 'a[href*="chaptered.php"]')) do count = count + 1 end
  return tostring(count)
end

-- ── Chapter text (image-based manga) ────────────────────────────────────────

function getChapterText(html, url)
  return ""
end

-- ── Reviews ─────────────────────────────────────────────────────────────────

-- Demonicscans comments come from /comments_api.php, verified against a real
-- response (sample: chapterid 100014521, 11 comments, fetched 2026-11-23).
--
-- Comment fields: id, username, content, created_at, likes, pinned,
-- edited_at, reply_count, root_id.
--
-- Login is required to POST comments (signin.php). Credentials can be stored
-- in the source settings (getSettingsSchema) and used by a future post-review
-- path.

function getBookReviews(bookUrl, index)
  local page = LIB("catalog").nextIndex(index)
  local body = fetchMangaPage(bookUrl)
  if not body then return { items = {}, hasNext = false } end

  local chapterId = commentChapterId(body)
  if chapterId == "" then return { items = {}, hasNext = false } end

  local data = fetchComments(chapterId, page)
  if not data or not data.ok or not data.items then
    return { items = {}, hasNext = false }
  end

  local items = {}
  for _, c in ipairs(data.items) do
    local content = string_clean(tostring(c.content or ""))
    if content ~= "" and not c.deleted then
      local item = {
        id     = tostring(c.id or ""),
        author = string_clean(tostring(c.username or "")),
        time   = tostring(c.created_at or ""),
        content = content,
        likes  = tonumber(c.likes) or 0,
      }
      if c.pinned then item.pinned = true end
      if c.edited_at then item.edited = true end
      if c.reply_count and tonumber(c.reply_count) > 0 then
        item.replies = tonumber(c.reply_count)
      end
      table.insert(items, item)
    end
  end

  local total = tonumber(data.total) or 0
  local offset = tonumber(data.offset) or 0
  local hasNext = (#items > 0) and (offset + #items < total)
  return { items = items, hasNext = hasNext }
end

-- ── Settings (login credentials for posting comments) ───────────────────────

function getSettingsSchema()
  return {
    {
      key     = "demonicscans_username",
      type    = "text",
      label   = "Username",
      current = get_preference("demonicscans_username") or "",
    },
    {
      key     = "demonicscans_password",
      type    = "password",
      label   = "Password",
      current = get_preference("demonicscans_password") or "",
    },
  }
end
