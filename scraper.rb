require 'scraperwiki'
require 'mechanize'
require 'date'
require 'logger'

base_url = "https://online.unley.sa.gov.au/ePathway/Production/Web/GeneralEnquiry/"
url = "#{base_url}enquirylists.aspx"

agent = Mechanize.new do |a|
  a.keep_alive = true
  # a.log = Logger.new $stderr
  # a.agent.http.debug_output = $stderr
  # a.verify_mode = OpenSSL::SSL::VERIFY_NONE
end

p "Getting first page"
first_page = agent.get url
url_query = url + '?' + first_page.body.scan(/js=-?\d+/)[0]  # enable JavaScript
first_page = agent.get url_query

p "Selecting List of Development Applications and clicking Next"
first_page_form = first_page.forms.first
first_page_form.radiobuttons[0].click
search_page = first_page_form.click_button

p "Clicking Date Lodged"
search_form = search_page.forms.first
search_form['__EVENTTARGET'] = 'ctl00$MainBodyContent$mGeneralEnquirySearchControl$mTabControl$tabControlMenu'
search_form['__EVENTARGUMENT'] = '3'
search_page = agent.submit(search_form)

p "Searching"
search_form = search_page.forms.first
# get the button you want from the form
button = search_form.button_with(:value => "Search")
# submit the form using that button
summary_page = agent.submit(search_form, button)

count = 0
das_data = []
while summary_page
  table = summary_page.root.at_css('.ContentPanel')
  headers = table.css('th').collect { |th| th.inner_text.strip } 

  das_data = das_data + table.css('.ContentPanel, .AlternateContentPanel').collect do |tr| 
    tr.css('td').collect { |td| td.inner_text.strip }
  end

  next_page_img = summary_page.root.at_xpath("//td/input[contains(@src, 'nextPage')]")
  summary_page = nil
  if next_page_img
    count += 1
    if count > 50  # safety precaution
      p "Stopping paging after " + count.to_s + " pages."
      break
    end
    next_page_path = next_page_img['onclick'].split(',').find { |e| e =~ /.*PageNumber=\d+.*/ }.gsub('"', '').strip
    p "Next page: " + next_page_path
    summary_page = agent.get "#{base_url}#{next_page_path}"
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
  if page_info['description'].strip == ''
    page_info['description'] = 'No description provided'
  end
  
  page_info
end

das.each do |record|
  ScraperWiki.save_sqlite(['council_reference'], record)
end

p "Complete."
