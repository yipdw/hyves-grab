local url_count = 0
local new_url_count = 0

read_file = function(file)
  if file then
    local f = io.open(file)
    local data = f:read("*all")
    f:close()
    return data
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

add_urls_from_pager = function(html, urls, hostname)
  local name = string.match(html, "name: '([^']+)'")
  local num_pages = to_number(html, string.match("nrPages: ([0-9]+)"))
  local extra = string.match(html, "extra: '([^']+)'")

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

wget.callbacks.get_urls = function(file, url, is_css, iri)
  -- progress message
  url_count = url_count + 1
  if url_count % 5 == 0 then
    io.stdout:write("\r - Downloaded "..url_count.." URLs. Discovered "..new_url_count.." URLs")
    io.stdout:flush()
  end


  local urls = {}
  local html = nil
  local hostname = string.match(url, "http://([^/]+)")

  -- paginate the friends (quickfinder_member_friends)
  if string.match(url, "hyves.nl/vrienden/") or string.match(url, "hyves.nl/friends/") or
  -- paginate the photos (albumlistwithpreview)
  string.match(url, "hyves.nl/fotos/") or string.match(url, "hyves.nl/photos/") or
  -- paginate the group members (quickfinder_hub_members)
  string.match(url, "hyves.nl/leden/") or string.match(url, "hyves.nl/members/") or
  -- paginate the blog (blog_mainbody / hub_content)
  string.match(url, "hyves.nl/blog/") then
    html = read_file(file)
    add_urls_from_pager(html, urls, hostname)
  end

  -- TODO: paginate other stuff
  -- TODO: check throttle
  -- TODO: check if wget will parse out the urls from the html fragment from the pagination request
  -- TODO: grab photos
end

