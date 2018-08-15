require 'scraperwiki'
require 'mechanize'
require 'date'
require 'logger'

base_url = "https://online.unley.sa.gov.au/ePathway/Production/Web/GeneralEnquiry/"
url = "#{base_url}enquirylists.aspx"

agent = Mechanize.new do |a|
 a.keep_alive = true # to avoid a "Net::HTTP::Persistent::Error:too many connection resets" condition
                     # https://github.com/tenderlove/mechanize/issues/123#issuecomment-6432074

  # a.log = Logger.new $stderr
  # a.agent.http.debug_output = $stderr
  # a.verify_mode = OpenSSL::SSL::VERIFY_NONE
end

first_page = agent.get url
p first_page.title.strip
first_page_form = first_page.forms.first
# select the "List of Development Applications" radio button
first_page_form.radiobuttons[0].click
search_page = first_page_form.click_button

# select the "Date Lodged" tab
search_form = search_page.forms.first
search_form['__EVENTTARGET'] = 'ctl00$MainBodyContent$mGeneralEnquirySearchControl$mTabControl$tabControlMenu'
search_form['__EVENTARGUMENT'] = '3'
search_form['__LASTFOCUS'] = ''
search_form['__VIEWSTATEENCRYPTED'] = ''
search_form['ctl00$MainBodyContent$mGeneralEnquirySearchControl$mEnquiryListsDropDownList'] = '10'
search_form['ctl00$MainBodyContent$mGeneralEnquirySearchControl$mTabControl$ctl04$mStreetNameTextBox'] = ''
search_form['ctl00$MainBodyContent$mGeneralEnquirySearchControl$mTabControl$ctl04$mStreetNumberTextBox'] = ''
search_form['ctl00$MainBodyContent$mGeneralEnquirySearchControl$mTabControl$ctl04$mStreetTypeDropDown'] = '(any)'
search_form['ctl00$MainBodyContent$mGeneralEnquirySearchControl$mTabControl$ctl04$mSuburbTextBox'] = ''
search_form['ctl00$mHeight'] = '807'
search_form['ctl00$mWidth'] = '1184'
# search_form['hiddenInputToUpdateATBuffer_CommonToolkitScripts'] = '1'
# date_lodged_link = search_page.link_with(text: 'Date Lodged')
p "Clicking Date Lodged tab"
# agent.redirect_ok = false
search_page = agent.submit(search_form, nil, {
'Host' => 'online.unley.sa.gov.au',
'Connection' => 'keep-alive',
'Cache-Control' => 'max-age=0',
'Origin' => 'https://online.unley.sa.gov.au',
'Upgrade-Insecure-Requests' => '1',
'Content-Type' => 'application/x-www-form-urlencoded',
'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/68.0.3440.106 Safari/537.36',
'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
'Referer' => 'https://online.unley.sa.gov.au/ePathway/Production/Web/GeneralEnquiry/EnquirySearch.aspx',
'Accept-Encoding' => 'gzip, deflate, br',
'Accept-Language' => 'en-US,en;q=0.9'
})
# agent.redirect_ok = true

p "Searching"
p search_page.title.strip
search_form = search_page.forms.first
# get the button you want from the form
button = search_form.button_with(:value => "Search")
# submit the form using that button
summary_page = agent.submit(search_form, button)
p summary_page.title.strip

das_data = []
while summary_page
  table = summary_page.root.at_css('.ContentPanel')
  #p table
  headers = table.css('th').collect { |th| th.inner_text.strip } 
  p headers

  das_data = das_data + table.css('.ContentPanel, .AlternateContentPanel').collect do |tr| 
    tr.css('td').collect { |td| td.inner_text.strip }
  end

  next_page_img = summary_page.root.at_xpath("//td/input[contains(@src, 'nextPage')]")
  summary_page = nil
  if next_page_img
    p "Found another page"
    next_page_path = next_page_img['onclick'].split(',').find { |e| e =~ /.*PageNumber=\d+.*/ }.gsub('"', '').strip
    # summary_page = agent.get "#{base_url}#{next_page_path}"
  end
end

comment_url = 'mailto:pobox1@unley.sa.gov.au'

das = das_data.collect do |da_item|
  page_info = {}
  page_info['council_reference'] = da_item[headers.index('Number')]
  # There is a direct link but you need a session to access it :(
  page_info['info_url'] = url
  page_info['description'] = da_item[headers.index('Description')]
  page_info['date_received'] = Date.strptime(da_item[headers.index('Lodgement Date')], '%d/%m/%Y').to_s
  page_info['address'] = da_item[headers.index('Location')]
  page_info['date_scraped'] = Date.today.to_s
  page_info['comment_url'] = comment_url
  
  page_info
end

das.each do |record|
    ScraperWiki.save_sqlite(['council_reference'], record)
end

