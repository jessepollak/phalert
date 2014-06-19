request = require 'request'
$ = require 'cheerio'
through = require 'through2'
Promise = require 'bluebird'
debug = require('debug')('notify')
Firebase = require 'firebase'

# try to load environment variables from a .env file, but ignore
# if it fails
try
  env = require 'node-env-file'
  env(__dirname + '/.env')
catch e

twilio = require('twilio')(process.env.TWILIO_ID, process.env.TWILIO_SECRET)

BASE_URL = 'http://www.producthunt.com'

DOMAINS_KEY = 'domains'
SEND_KEY = 'sent'
firebase = new Firebase 'https://phnotifier.firebaseio.com/'
domainRef = firebase.child(DOMAINS_KEY);
sentRef = firebase.child(SEND_KEY)

# firebase keys cannot contain ".", "#", "$", "/", "[", or "]"
domainToKey = (domain) ->
  domain.replace /\./g, '-'
domainFromKey = (key) ->
  key.replace /-/g, '.'

# turn a Date into the format MM-DD-YYYY
todayToKey = ->
  date = new Date()
  [date.getMonth(), date.getDay(), date.getFullYear()].join('-')

# we do a full set for the mapping of domain -> numbers that have
# already been sent to for the day
setSentMap = (map) ->
  # escape domains
  safeMap = {}
  for domain, numbers of map
    safeMap[domainToKey(domain)] = numbers

  todayRef = sentRef.child(todayToKey())
  new Promise (resolve, reject) ->
    todayRef.set safeMap, ->
      resolve(true)

# get the mapping of domain -> numbers that we have already
# sent to today
getSentMap = ->
  todayRef = sentRef.child(todayToKey())
  new Promise (resolve, reject) ->
    todayRef.once 'value', (snapshot) ->
      map = snapshot.val()

      unsafeMap = {}
      for key, numbers of map
        unsafeMap[domainFromKey(key)] = numbers

      resolve unsafeMap

# get the mapping of domain -> number that someone wants a text
# sent to
getDomainMap =  ->
  new Promise (resolve, reject) ->
    domainRef.once 'value', (snapshot) ->
      domainMap = {}
      for domain, numbers of snapshot.val()
        # unescape the domain names
        domain = domainFromKey domain

        # trim out any bad domains that aren't of the form test.com
        if domain.match /^([A-Za-z0-9_]+\.)+([a-z])+$/
          domainMap[domain] = (obj.number for key, obj of numbers)

      resolve(domainMap)

# send a text to an array of numbers for a given domain
sendText = (result, domain, numbers) ->
  numbers = [numbers] if typeof(numbers) == "string"
  promises = []
  for number in numbers
    promises.push(new Promise (resolve, reject) ->
      twilio.messages.create(
        {
          from: '+12407884901',
          to: number,
          body: "Your domain #{domain} has been mentioned on Product Hunt.
                Read more here: #{result.comments}."
        },
        (err, message) ->
          if err
            debug "[not sent] #{number}, #{domain}, #{err.message}"
          else
            debug "[sent] #{number}, #{domain}"

          resolve()
      )
    )

  promises

# the links to the actual products on the home page are hidden
# behind a Product Hunt short URL. To get the actual URL,
# we send a HEAD request to the PH short URL and follow the redirects
# to the end
findExternalDomains = (urls) ->
  new Promise (resolve, reject) ->
    promises = urls.map (obj) ->
      new Promise (resolve, reject) ->
        request.head { uri: obj.external, timeout: 25000 }, (err, resp, body) ->
          if err
            console.log "ERROR: #{err}"
            return resolve null

          obj.external = resp.request.uri.href
          resolve obj

    Promise.all(promises).then(resolve)

getAllMatches = ->
  new Promise (resolve, reject) ->
    # get the Product Hunt home page
    request.get BASE_URL, (err, resp, body) ->
      if err
        msg = "ERROR: #{err}"
        return reject(msg)

      # find all of today's posts
      $body = $.load body
      posts = $body('.today .post')
      # retrieve the list of external URLs and comment URLs for today's
      # posts
      urls = posts.map (i, el) ->
        external: BASE_URL + $('.post-url', el)[0].attribs.href
        comments: BASE_URL + $('.view-discussion', el)[0].attribs.href

      # turn Product Hunt short URLs into actual domains
      findExternalDomains(urls.toArray()).then(resolve)

processMatches = (results) ->
  new Promise (resolve, reject) ->
    textMessagesSent = []
    Promise.all([getDomainMap(), getSentMap()]).spread (domains, sent) ->
      sent = sent or {}
      for domain, numbers of domains
        for result in results
          if result?.external.match(domain)

            # only send text messages to numbers that haven't already
            # been texted to for the given domain
            alreadySentTo = sent[domain] or []
            sendTo = []
            for number in numbers
              if number in alreadySentTo
                debug "[ignore][already sent] #{number}, #{domain}"
              else
                sendTo.push(number)
                alreadySentTo.push(number)
            sent[domain] = alreadySentTo

            promises = sendText(result, domain, sendTo)
            textMessagesSent = textMessagesSent.concat(promises)

      # once all text messages are sent we can store all the numbers
      # that were texted and resolve
      Promise.all(textMessagesSent)
        .then(setSentMap.bind(null, sent))
        .then(resolve)

run = (cb) ->
  firebase.auth process.env.FIREBASE_SECRET, ->
    getAllMatches()
      .then processMatches
      .then cb

run ->
  process.exit()
