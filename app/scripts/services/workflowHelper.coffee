'use strict'

angular.module('thingifyApp')

.service 'workflowHelper', ($q, thingiverseAPI) ->
  access_token = ''

  set_access_token: (t) ->
    access_token = t

  create_thing: (file, thing_data) ->
    file.status = 'Creating'
    deferred = $q.defer()
    req = thingiverseAPI.create_thing(thing_data, access_token)
    req.then (res) ->
      file.status = 'Created'
      file.tv_obj = res.data
      deferred.resolve(file)
    req.error ->
      file.status = 'Failed Creation'
      deferred.reject(file)
    deferred.promise

  request_upload: (file) ->
    file.status = 'Pre-registering upload'
    deferred = $q.defer()
    req = thingiverseAPI.request_upload(file, access_token)
    req.then (res) ->
      file.status = 'Pre-registered Upload'
      file.finalize_url = res.data.fields.success_action_redirect
      file.upload_instructions = res.data
      deferred.resolve(file)
    req.error (res) ->
      file.status = 'Upload Pre-registration failed'
      deferred.reject(file)
    deferred.promise

  upload_file: (file) ->
    file.status = "Uploading"
    deferred = $q.defer()
    req = thingiverseAPI.s3_upload(file, file.upload_instructions)
    req.error (res) ->
      # will always error, because of the success_action_redirect
      unless (res.xhr.status or res.xhr.response or res.xhr.responseType)
        # this means the error was due to a redirect (303) which actually
        #  means the file was uploaded successfully
        file.status = 'Uploaded'
        deferred.resolve(file)
      else
        # This looks like a real error :(
        file.status = 'Failed Upload'
        deferred.reject(file)
    deferred.promise


  finalize_upload: (file) ->
    file.status = "Finalizing Upload"
    deferred = $q.defer()
    deferred.promise.error = deferred.promise.catch

    fu = thingiverseAPI.finalize_upload(file.finalize_url, access_token)
    fu.then (res) ->
      # upload finalized
      file.status = 'Upload Finalized'
      file.finalized = true
      deferred.resolve(file)
    fu.error () ->
      # upload finalized
      file.status = 'Upload not finalised (don\'t worry)'
      file.finalized = false
      deferred.reject(file)
    deferred.promise


  publish_thing: (file) ->
    file.status = 'Publishing Thing'
    deferred = $q.defer()
    deferred.promise.error = deferred.promise.catch

    fu = thingiverseAPI.finalize_upload(file.finalize_url, access_token)
    fu.then (res) ->
      # upload finalized
      file.status = 'Published'
      file.published = true
      deferred.resolve(file)
    fu.error () ->
      # upload finalized
      file.status = 'Publish failed'
      deferred.reject(file)
    deferred.promise


  delete_thing: (file) ->
    file.status = 'Deleting Thing'
    deferred = $q.defer()
    deferred.promise.error = deferred.promise.catch

    fu = thingiverseAPI.finalize_upload(file.finalize_url, access_token)
    fu.then (res) ->
      # upload finalized
      file.status = 'Thing Deleted'
      deferred.resolve(file)
    fu.error () ->
      # upload finalized
      file.status = 'Delete Failed'
      deferred.reject(file)
    deferred.promise
