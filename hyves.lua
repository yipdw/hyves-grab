dofile("urlcode.lua")

local url_count = 0
local new_url_count = 0
local hyves_username = os.getenv("hyves_username")
local photo_urls = {}
local tries = 0

read_file = function(file)
  if file then
    local f = io.open(file)
    local data = f:read("*all")
    f:close()
    return data or ""
  else
    return ""
  end
end

read_file_short = function(file)
  if file then
    local f = io.open(file)
    local data = f:read(4096)
    f:close()
    return data or ""
  else
    return ""
  end
end


-- range(a) returns an iterator from 1 to a (step = 1)
-- range(a, b) returns an iterator from a to b (step = 1)
-- range(a, b, step) returns an iterator from a to b, counting by step.
-- http://lua-users.org/wiki/RangeIterator
function range(a, b, step)
  if not b then
    b = a
    a = 1
  end
  step = step or 1
  local f =
  step > 0 and
  function(_, lastvalue)
    local nextvalue = lastvalue + step
    if nextvalue <= b then return nextvalue end
  end or
  step < 0 and
  function(_, lastvalue)
    local nextvalue = lastvalue + step
    if nextvalue >= b then return nextvalue end
  end or
  function(_, lastvalue) return lastvalue end
  return f, nil, a - step
end

-- http://stackoverflow.com/a/14899740/1524507
function html_unescape(str)
  local map={ ["lt"]="<", ["gt"]=">", ["amp"]="&", ["quot"]='"', ["apos"]="'" }
  str = string.gsub( str, '(&(#?)([%d%a]+);)', function(orig,n,s)
    return map[s] or n=="#" and string.char(s) or orig
  end )
  return str
end

-- http://lua-users.org/wiki/StringTrim
function trim1(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

add_urls_from_pager = function(html, urls, hostname, current_url)
  local name = string.match(html, "name:%s*'([^']+)'")
  local num_pages = tonumber(string.match(html, "nrPages:%s*([0-9]+)"))
  local extra = string.match(html, "extra:%s*'([^']+)'")

  io.stdout:write("\n  Pager: url="..current_url.." name="..tostring(name).." num_pages="..tostring(num_pages).."\n")
  io.stdout:flush()

  if not name or not num_pages or not extra then
    -- io.stdout:write("\nPager not found: url="..current_url.." name="..tostring(name).." num_pages="..tostring(num_pages).." extra="..tostring(extra).."\n")
    -- io.stdout:flush()
    return
  end

  io.stdout:write("     ok\n")
  io.stdout:flush()

  for page_number in range(1, num_pages) do

    local fields = {}

    fields["pageNr"] = page_number
    fields["config"] = "hyvespager-config.php"
    fields["showReadMoreLinks"] = "false"
    fields["extra"] = extra

    table.insert(urls, {
      url="http://"..hostname.."/index.php?xmlHttp=1&module=pager&action=showPage&name="..name,
      post_data=cgilua.urlcode.encodetable(fields)
    })

    new_url_count = new_url_count + 1
  end
end

add_urls_from_pager_main_page = function(html, urls, hostname, pager_name, current_url)
  local pager_pattern_name = pager_name:gsub("%-", "%%-")
  local num_pages, extra = string.match(html, "name:%s*'"..pager_pattern_name.."'[^}]-nrPages:%s*([0-9]+)[^}]-extra:%s*'([^']+)'")
  num_pages = tonumber(num_pages)
  
  io.stdout:write("\n  Pager: url="..current_url.." name="..tostring(pager_name).." num_pages="..tostring(num_pages).."\n")
  io.stdout:flush()

  if not num_pages or not extra then
    -- io.stdout:write("\nPager not found: url="..current_url.." name="..tostring(pager_name).." num_pages="..tostring(num_pages).." extra="..tostring(extra).."\n")
    -- io.stdout:flush()
    return
  end

  -- io.stdout:write("\nPager found: url="..current_url.." name="..tostring(pager_name).." num_pages="..tostring(num_pages).." extra="..tostring(extra).."\n")
  -- io.stdout:flush()

  io.stdout:write("     ok\n")
  io.stdout:flush()

  for page_number in range(1, num_pages) do

    local fields = {}

    fields["pageNr"] = page_number
    fields["config"] = "hyvespager-config.php"
    fields["showReadMoreLinks"] = "false"
    fields["extra"] = extra

    table.insert(urls, {
      url="http://"..hostname.."/index.php?xmlHttp=1&module=pager&action=showPage&name="..pager_name,
      post_data=cgilua.urlcode.encodetable(fields)
    })

    new_url_count = new_url_count + 1
  end

end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  if verdict then
    local sleep_time = 1.0 * (math.random(75, 125) / 100.0)

    if string.match(urlpos["url"]["url"], "hyves%-static.net") then
      -- We should be able to go fast on images since that's what a web browser does
      sleep_time = 0
    end
    
    -- stop infinite loop
    if string.match(parent["url"], "action=showMemberDetails&k=([%w_-])") ==
    string.match(urlpos["url"]["url"], "action=showMemberDetails&k=([%w_-])") and
    depth > 5 then
      io.stdout:write("\nRejecting possible infinite loop (showMemberDetails)\n")
      io.stdout:flush()
      return false
    end

    if sleep_time > 0.001 then
      -- io.stdout:write("\nSleeping=".. sleep_time .." url="..urlpos["url"]["url"].." verdict="..tostring(verdict).."\n")
      -- io.stdout:flush()
      os.execute("sleep " .. sleep_time)
    end
  end

  return verdict
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  local html = read_file_short(http_stat["local_file"])
  local sleep_time = 20
  local status_code = http_stat["statcode"]

  -- not sure why checking the message didn't work
  -- string.match(html, "Try again in a moment") or

  -- Checking status code might be a problem if the page is errorring
  -- due to unrelated issues
  if status_code == 500 then
    io.stdout:write("\nHyves angered (code "..http_stat.statcode.."). Sleeping for ".. sleep_time .." seconds.\n")
    io.stdout:flush()

-- if joepie91 wants infinite tries, then joepie91 gets infinite tries
--    if tries > 9000 then
--      io.stdout:write("\nLikely banned. Giving up.\n")
--      io.stdout:flush()
--      return wget.actions.ABORT
--    end

    -- Note that wget has its own exponential backoff to this time as well
    os.execute("sleep " .. sleep_time)
    tries = tries + 1
    return wget.actions.CONTINUE
  end

  tries = 0
  return wget.actions.NOTHING
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  -- progress message
  url_count = url_count + 1
  if url_count % 2 == 0 then
    io.stdout:write("\r - Downloaded "..url_count.." URLs. Discovered "..new_url_count.." URLs.")
    io.stdout:flush()
  end

  local urls = {}
  local html = nil
  local hostname = string.match(url, "http://([^/]+)")

  -- paginate all the things!
  if string.match(url, "hyves.nl/[%w_-]+/?$") then
    if not html then
      html = read_file(file)
    end
    io.stdout:write("\n  Trying to paginate "..string.match(url, "hyves.nl/([%w_-]+)/?$").."\n")
    io.stdout:flush()
    add_urls_from_pager(html, urls, hostname, url)
  end

  -- paginate all the things on homepage!
  if string.match(url, "hyves.nl/$") then
    if not html then
      html = read_file(file)
    end
    
    for page_name in string.gmatch(html, "name:%s*'([^']+)'") do
      io.stdout:write("\n  Trying to paginate "..page_name.."\n")
      io.stdout:flush()

      add_urls_from_pager_main_page(html, urls, hostname, page_name, url)
    end

    -- grab the music
    for ue in string.gmatch(html, "ue:%s*'([a-zA-Z0-9/+]+)'") do
      io.stdout:write("\n  ue: "..ue)

      local p_file = assert(io.popen("python aplayer_swf.py "..ue, 'r'))
      local ue_url = assert(p_file:read('*a'))
      ue_url = trim1(ue_url)
      p_file:close()

      io.stdout:write("\n  music: "..ue_url.."\n")
      io.stdout:flush()

      table.insert(urls, { url=ue_url })
      new_url_count = new_url_count + 1
    end
  end

  -- Whitelist the photo urls to be downloaded
  if string.match(url, "hyves.nl/fotos/") or
  string.match(url, "hyves.nl/photos/") or
  string.match(url, "hyves.nl/album/") then
    if not html then
      html = read_file(file)
    end

    for requisite_url in string.gmatch(html, "=['\"](http[%w%.:/-]+hyves%-static%.net[^'\"]+)['\"]") do
      -- io.stdout:write("\nFound photo url="..requisite_url.."\n")
      -- io.stdout:flush()
      photo_urls[requisite_url] = true
    end
  end

  -- scrape out the urls from the html fragment from the pagination request
  -- or urls from the html fragment of the photo comments
  if string.match(url, "/index.php%?xmlHttp=1&module=pager") or
  string.match(url, "module=PhotoBrowser&action=postGetSocialPage") then
    if not html then
      html = read_file(file)
    end

    -- links
    local hyves_username_pattern = hyves_username:gsub("%-", "%%-")
    for requisite_url in string.gmatch(html, "=['\"](https?://"..hyves_username_pattern.."%.hyves%.nl/[^'\"]+)['\"]") do
      table.insert(urls, { url=html_unescape(requisite_url) })
      -- io.stdout:write("\nPager new url="..requisite_url.."\n")
      -- io.stdout:flush()
      new_url_count = new_url_count + 1
    end

    -- photos
    for requisite_url in string.gmatch(html, "=['\"](http[%w%.:/-]+hyves%-static%.net[^'\"]+)['\"]") do
      table.insert(urls, { url=html_unescape(requisite_url) })
      -- io.stdout:write("\nPager new media url="..requisite_url.."\n")
      -- io.stdout:flush()
      new_url_count = new_url_count + 1

      -- Whitelist the photo url to be downloaded.
      if string.match(url, "albumlistwithpreview") or string.match(url, "fr_it_ph_list_redesign") then
        -- io.stdout:write("\nFound photo url="..requisite_url.."\n")
        -- io.stdout:flush()
        photo_urls[requisite_url] = true
      end
    end
  end

  -- Grab large size photos (change 16 into a 6 ???) from photo album only.
  -- Grab videos (change 16 to a 7 and change extension to flv)
  -- We check the table to see if we are coming from an album and not from a
  -- photo comment page. Getting the comment page on an image from a comment
  -- page would be recursion across users.
  if string.match(url, "http://[0-9].media.hyves%-static.net/[0-9]+/16/[%w_-]+/[0-9]+/[%w.]+") and
  photo_urls[url] then
    local hostnum, img_id, secret, something, filename = string.match(url, "http://([0-9]).media.hyves%-static.net/([0-9]+)/16/([%w_-]+)/([0-9]+)/([%w.]+)")
    local photo_url = "http://"..hostnum..".media.hyves-static.net/"..img_id.."/6/"..secret.."/"..something.."/"..filename
    table.insert(urls, { url=photo_url })
    new_url_count = new_url_count + 1

    -- It might be a video, so try to grab that as well
    local video_url = "http://"..hostnum..".media.hyves-static.net/"..img_id.."/7/"..secret.."/"..something.."/"..filename:gsub("jpeg", "flv")
    table.insert(urls, { url=video_url })

    -- grab the html fragment containing the photo comments and the "respects"
    local photo_meta_url = "http://"..hyves_username..".hyves.nl/?module=PhotoBrowser&action=postGetSocialPage"
    -- the order of these fields actually matters..
    -- the postman secret should be same as GP cookie value
    local post_data_fields = "itemType=4&postman_secret=deadbeef&itemApiId=&itemId="..img_id.."&itemSecret="..secret

    table.insert(urls, {
      url=photo_meta_url,
      post_data=post_data_fields
    })

    new_url_count = new_url_count + 1
  end

  return urls
end

