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
        file.uploaded = true
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

    req = thingiverseAPI.finalize_upload(file.finalize_url, access_token)
    req.then (res) ->
      # upload finalized
      file.status = 'Upload Finalized'
      file.finalized = true
      deferred.resolve(file)
    req.error () ->
      # upload finalized
      file.status = 'Upload not finalised (don\'t worry)'
      deferred.reject(file)
    deferred.promise

  publish_thing: (file) ->
    file.status = 'Publishing Thing'
    deferred = $q.defer()
    deferred.promise.error = deferred.promise.catch

    req = thingiverseAPI.finalize_upload(file.finalize_url, access_token)
    req.then (res) ->
      file.status = 'Published'
      file.published = true
      deferred.resolve(file)
    req.error () ->
      file.status = 'Publish failed'
      deferred.reject(file)
    deferred.promise

  add_thing_to_collection: (file) ->
    file.status = 'Adding thing to collection'
    deferred = $q.defer()
    deferred.promise.error = deferred.promise.catch
    req = thingiverseAPI.add_thing_to_collection(file.for_collection, file.tv_obj.id, access_token)
    req.then (file) ->
      file.status = 'Added to collection'
      file.cate = true
      deferred.resolve(file)
    req.error (file) ->
      file.status = 'Failed add to collection'
      deferred.reject(file)
    deferred.promise

  delete_thing: (file) ->
    file.status = 'Deleting Thing'
    deferred = $q.defer()
    deferred.promise.error = deferred.promise.catch

    req = thingiverseAPI.finalize_upload(file.finalize_url, access_token)
    req.then (res) ->
      # upload finalized
      file.status = 'Thing Deleted'
      deferred.resolve(file)
    req.error () ->
      # upload finalized
      file.status = 'Delete Failed'
      deferred.reject(file)
    deferred.promise
