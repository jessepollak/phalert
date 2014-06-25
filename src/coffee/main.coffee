$ = require 'jquery'

DOMAIN_REGEX = /^([A-Za-z0-9_]+\.)+([a-z])+$/
FIREBASE_URL = 'https://phnotifier.firebaseio.com/'
DOMAINS_KEY = 'domains'
submitting = false

domainToKey = (domain) ->
  domain.replace /\./g, '-'
submit = (e) ->
  e.preventDefault()
  return if submitting
  firebase = new Firebase FIREBASE_URL
  domainRef = firebase.child DOMAINS_KEY
  submitting = true
  domain = $('input[name="domain"]').val()
  number = formatE164('US', $('input[name="number"]').val())
  $('.success-message, .error-message').css opacity: 0
  domainRef.child(domainToKey(domain)).push number: number, submitCallback
submitCallback = (err) ->
  submitting = false
  if err
    $err = $('.error-message')
    $err.find('.error').text err
    $err.animate opacity: 1
  else
    $domain = $('input[name="domain"]')
    $succ = $('.success-message')

    domain = $domain.val()
    $succ.find('.domain').text domain
    $succ.animate opacity: 1

    $('input[type="text"]').map ->
      $(this).val('').trigger('keyup')

    $domain.focus()
enableForm = ->
  $submit = $('input[type="submit"]')
  if validForm()
    $submit.removeAttr 'disabled'
  else
    $submit.attr 'disabled', 'disabled'
validateField = (validationFn) ->
  (e) ->
    $input = $(this)
    valid = validationFn $input.val()
    $input.toggleClass 'valid', valid
validDomain = (str) ->
  !!str.match(DOMAIN_REGEX)
validNumber = (str) ->
  !!isValidNumber str, 'US'
validForm = ->
  $('form').find('input[type="text"]')
    .toArray()
    .map ((el) -> $(el).hasClass 'valid')
    .reduce ((prev, cur) -> cur and prev), true

$ ->
  $('form').on 'submit', submit
  $('input[name="domain"]').on 'keyup', validateField(validDomain)
  $('input[name="number"]').on 'keyup', validateField(validNumber)
  $('input[type="text"]').on 'keyup', enableForm
