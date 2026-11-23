id       = "nhentai"
name     = "nhentai"
version  = "1.0.0"
baseUrl  = "https://nhentai.net/"
language = {"en", "es", "fr"}
content_type = "manga"
icon     = "https://raw.githubusercontent.com/Stlucifer15t/external-sources/refs/heads/v2/icons/doujinhentai.png"

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

-- Extract gallery id from a /g/{id}/ URL.
local function galleryId(bookUrl)
  local u = tostring(bookUrl or "")
  return u:match("/g/(%d+)/?$") or u:match("/g/(%d+)") or ""
end

-- Gallery API JSON (includes title, cover, tags, comments).
local function fetchGalleryApi(gid, page)
  local url = baseUrl .. "api/v2/galleries/" .. gid .. "?include=comments&page=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return nil end
  return json_parse(r.body)
end

-- Gallery page HTML (fallback when API is unavailable).
local function fetchGalleryPage(bookUrl)
  return LIB("fetch").page(bookUrl)
end

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "?page=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, a in ipairs(html_select(r.body, 'a[href^="/g/"]')) do
    local gid = a.href:match("/g/(%d+)")
    if gid then
      local titleEl = html_select_first(a.html, ".caption, .pretty")
      local title = titleEl and string_clean(titleEl.text) or string_clean(a.text)
      if title == "" then title = string_clean(a.title or "") end
      if title ~= "" then
        table.insert(items, {
          title = title,
          url   = absUrl(a.href),
        })
      end
    end
  end
  return { items = items, hasNext = #items > 0 }
end

-- ── Search ──────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "search/?q=" .. LIB("catalog").urlEncode(query) .. "&page=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, a in ipairs(html_select(r.body, 'a[href^="/g/"]')) do
    local gid = a.href:match("/g/(%d+)")
    if gid then
      local titleEl = html_select_first(a.html, ".caption, .pretty")
      local title = titleEl and string_clean(titleEl.text) or string_clean(a.text)
      if title == "" then title = string_clean(a.title or "") end
      if title ~= "" then
        table.insert(items, {
          title = title,
          url   = absUrl(a.href),
        })
      end
    end
  end
  return { items = items, hasNext = #items > 0 }
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local gid = galleryId(bookUrl)
  if gid == "" then return nil end
  local data = fetchGalleryApi(gid, 1)
  if data and data.title then
    local t = data.title.pretty or data.title.english or data.title.japanese or ""
    if t ~= "" then return string_clean(t) end
  end
  local body = fetchGalleryPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1.title")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local gid = galleryId(bookUrl)
  if gid == "" then return nil end
  local data = fetchGalleryApi(gid, 1)
  if data and data.cover then return absUrl(data.cover) end
  if data and data.thumbnail then return absUrl(data.thumbnail) end
  local body = fetchGalleryPage(bookUrl)
  if not body then return nil end
  local src = html_attr(body, ".cover img, .gallery-cover img", "src")
  if src == "" then src = html_attr(body, "a.cover img", "src") end
  return src ~= "" and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  local gid = galleryId(bookUrl)
  if gid == "" then return nil end
  local data = fetchGalleryApi(gid, 1)
  if data and data.tags then
    local parts = {}
    for _, t in ipairs(data.tags) do
      local name = t.name or t["name"] or ""
      if name ~= "" then table.insert(parts, name) end
    end
    if #parts > 0 then return table.concat(parts, ", ") end
  end
  local body = fetchGalleryPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".description, .gallery-description")
  return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
  local gid = galleryId(bookUrl)
  if gid == "" then return {} end
  local data = fetchGalleryApi(gid, 1)
  if data and data.tags then
    local genres = {}
    for _, t in ipairs(data.tags) do
      local ns = t.namespace or ""
      local name = t.name or ""
      if ns ~= "" and name ~= "" then
        table.insert(genres, ns .. ": " .. name)
      elseif name ~= "" then
        table.insert(genres, name)
      end
    end
    return genres
  end
  local body = fetchGalleryPage(bookUrl)
  if not body then return {} end
  return LIB("meta").collectGenres(html_select(body, ".tag"))
end

-- ── Rating ──────────────────────────────────────────────────────────────────

function getBookRating(bookUrl)
  local gid = galleryId(bookUrl)
  if gid == "" then return nil end
  local data = fetchGalleryApi(gid, 1)
  if data and data.num_favorites then
    return tostring(data.num_favorites)
  end
  return nil
end

-- ── Chapters (gallery pages) ────────────────────────────────────────────────

function getChapterList(bookUrl)
  local gid = galleryId(bookUrl)
  if gid == "" then return {} end
  local data = fetchGalleryApi(gid, 1)
  if not data or not data.pages then return {} end

  local chapters = {}
  for i, p in ipairs(data.pages) do
    local url = absUrl("/g/" .. gid .. "/" .. i .. "/")
    table.insert(chapters, {
      title = "Page " .. tostring(i),
      url   = url,
    })
  end
  return chapters
end

function getChapterListHash(bookUrl)
  local gid = galleryId(bookUrl)
  if gid == "" then return nil end
  local data = fetchGalleryApi(gid, 1)
  if not data then return nil end
  return tostring(data.num_pages or 0) .. "|" .. tostring(data.upload_date or "")
end

-- ── Chapter text (nhentai pages are images; no text) ────────────────────────

function getChapterText(html, url)
  return ""
end

-- ── Reviews ─────────────────────────────────────────────────────────────────

-- nhentai comments come from the gallery API, verified against a real
-- response from https://nhentai.net/api/v2/galleries/699118?include=comments
-- (sample: gallery 699118, 77 comments, fetched 2026-11-23).
--
-- Comment fields: id, gallery_id, poster, post_date, body.
-- No per-comment rating, likes, spoiler, pinned or edited fields are
-- provided by the API — those keys are simply omitted.
--
-- Login is required to POST comments (site shows "Login or register to
-- post a comment"). Credentials can be stored in the source settings
-- (getSettingsSchema) and used by a future post-review path.

function getBookReviews(bookUrl, index)
  local page = LIB("catalog").nextIndex(index)
  local gid = galleryId(bookUrl)
  if gid == "" then return { items = {}, hasNext = false } end

  local data = fetchGalleryApi(gid, page)
  if not data then return { items = {}, hasNext = false } end

  local comments = data.comments or {}
  local items = {}
  for _, c in ipairs(comments) do
    local content = string_clean(tostring(c.body or ""))
    if content ~= "" then
      local item = {
        id     = tostring(c.id or ""),
        author = string_clean(tostring(c.poster or "")),
        time   = tostring(c.post_date or ""),
        content = content,
      }
      table.insert(items, item)
    end
  end

  local count = tonumber(data.comment_count) or 0
  local hasNext = (#items > 0) and (page * 50 < count)
  return { items = items, hasNext = hasNext }
end

-- ── Settings (login credentials for posting comments) ───────────────────────

function getSettingsSchema()
  return {
    {
      key     = "nhentai_username",
      type    = "text",
      label   = "Username",
      current = get_preference("nhentai_username") or "",
    },
    {
      key     = "nhentai_password",
      type    = "password",
      label   = "Password",
      current = get_preference("nhentai_password") or "",
    },
  }
end
