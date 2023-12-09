local context_manager = require("plenary.context_manager")
local with = context_manager.with
local open = context_manager.open
local xml = require("neotest.lib.xml")

--- @param classname string name of class
--- @param testname string name of test
--- @return string unique_key based on classname and testname
local build_unique_key = function(classname, testname)
	return classname .. "::" .. testname
end

TestParser = {}

function is_array(tbl)
	local index = 1
	for k, _ in pairs(tbl) do
		if k ~= index then
			return false
		end
		index = index + 1
	end
	return true
end

--- @param filename string
--- @return table { [test_name] = {
---   status = string,
---
--- { name = string,
---   status = string,
---   classname = string,
---   message = string }
--- }
---}
function TestParser.parse_html_gradle_report(filename)
	local test_classname = string.match(filename, "([^/]+)%.html")

	local data
	with(open(filename, "r"), function(reader)
		data = reader:read("*a")
	end)

	local xml_data = xml.parse(data).html.body.div.div[3]

	-- /html/body/div/div[3]/div/table/tbody/tr[1]/td[2]
	-- /html/body/div/div[3]/div[2]/table/tbody/tr[5]/td[2]
	-- /html/body/div/div[3]/div[2]/table/tbody/tr[1]/td[2]
	-- /html/body/div/div[3]/div/table/tbody/tr/td[1]
	-- /html/body/div/div[3]/div[2]/table/tbody/tr/td[2]
	local names
	if #xml_data.div == 0 then
		names = xml_data.div.table.tr
	elseif xml_data.div[2].table then
		names = xml_data.div[2].table.tr
	else
		for i, div in ipairs(xml_data.div) do
			if div.h2 == "Tests" then
				names = div.table.tr
			end
		end
	end

	if not is_array(names) then
		names = { names }
	end

	local testcases = {}
	for k, v in pairs(names) do
		if #v.td == 4 then
			-- /html/body/div/div[3]/div[2]/table/tbody/tr[4]/td[2]
			-- /html/body/div/div[3]/div[2]/table/tbody/tr[5]/td[2]
			local name = v.td[2][1]
			-- local name = v.td[2][1]
			local status = v.td[4][1]

			-- take out the parameterized part
			-- example: subtractAMinusBEqualsC(int, int, int)[1]
			-- becomes: subtractAMinusBEqualsC
			short_name = string.match(name, "([^%(%[]+)")
			local unique_key = build_unique_key(test_classname, short_name)

			if testcases[unique_key] == nil then
				testcases[unique_key] = {
					status = "passed",
					{ name = name, status = status, classname = test_classname },
				}
			else
				table.insert(testcases[unique_key], { name = name, status = status, classname = test_classname })
			end
		end
	end

	-- /html/body/div/div[3]/div[1]
	local failures
	if #xml_data.div == 0 then
		failures = {}
	else
		failures = xml_data.div[1].div or {}
	end

	if not is_array(failures) then
		failures = { failures }
	end

	for k, v in pairs(failures) do
		local name = v.a._attr.name
		local short_name = string.match(name, "([^%(%[]+)")
		local parameters = v.h3[1]
		local message = v.span.pre
		-- takes just the first line of the message
		message = string.match(message, "([^\n]+)")

		local unique_key = build_unique_key(test_classname, short_name)
		if testcases[unique_key] ~= nil then
			for k2, v2 in pairs(testcases[unique_key]) do
				if v2.name == name then
					testcases[unique_key].status = "failed"
					testcases[unique_key][k2].message = message
				end
			end
		end
	end

	return testcases
end

TestResults = {}

function TestResults.get_status()
	local status = "passed"
	for k, v in pairs(TestResults.testcases) do
		for k2, v2 in pairs(v) do
			if v2.status == "failed" then
				status = "failed"
			end
		end
	end
	return status
end

return TestParser
