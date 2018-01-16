{$, $$, SelectListView} = require 'atom-space-pen-views'
percentile = require 'percentile'
moment = require 'moment'
# moment.locale('sk')
class JobSelectorView extends SelectListView
  initialize: (jobs, controller, projectPath) ->
    super

    @jobs = jobs
    @controller = controller
    @projectPath = projectPath
    {@alwaysSuccess, @unstable, @alwaysFailed, @total} = @controller.statistics(@jobs)
    @addClass('overlay from-top')
    @setItems jobs
    @panel ?= atom.workspace.addModalPanel(item: this)
    @focusFilterEditor()
    $$(@extraContent(@)).insertBefore(@error)
    @handleEvents()
    @panel.show()

  getFilterKey: -> 'name'

  extraContent: (thiz) ->
    if thiz.jobs?.length > 0
      commit = thiz.jobs[0].commit
      ref = thiz.jobs[0].ref
    return ->
      @div class: 'block', =>
        @div class: 'block', =>
          @button outlet: 'allButton', class: 'btn btn-info', ' All', =>
            @span class: 'badge badge-small', thiz.jobs?.length
          @div class: 'btn-group', =>
            @button outlet: 'alwaysSuccessButton', class: 'btn btn-success', ' Always Success', =>
              @span class: 'badge badge-small', thiz.alwaysSuccess?.length
            @button outlet: 'sometimesFailedButton', class: 'btn btn-warning', ' Sometimes Failed', =>
              @span class: 'badge badge-small', thiz.unstable?.length
            @button outlet: 'alwaysFailedButton', class: 'btn btn-error', ' Always Failed', =>
              @span class: 'badge badge-small', thiz.alwaysFailed?.length
        @div class: 'block', =>
          @span class: 'icon icon-git-commit', commit?.message
          @span class: 'text-muted', " #{ref} / #{commit?.short_id}"
          @span class: 'icon icon-clock', moment(commit?.created_at).format('lll')

  handleEvents: ->
    @wireOutlets(@)

    @alwaysSuccessButton.on 'mouseover', (e) =>
      @setItems @alwaysSuccess

    @sometimesFailedButton.on 'mouseover', (e) =>
      @setItems @unstable

    @alwaysFailedButton.on 'mouseover', (e) =>
      @setItems @alwaysFailed

    @allButton.on 'mouseover', (e) =>
      @setItems @jobs


  populateList: () ->
    @items?.sort (a, b) ->
      return -1 if a.name < b.name
      return 1 if a.name > b.name
      return -1 if a.id < b.id
      return 1 if a.id > b.id
      return 0

    @maxDuration = @items?.reduce( ((max, j) ->
      Math.max(max, j.duration)
    ), 0 )

    if @items?.length > 0
      @averageDuration = percentile(50, @items, (item) -> item.duration).duration

    super

  viewForItem: (job) ->
    type = @controller.toType(job, @averageDuration)

    artifactIcon = if job.artifacts_file then "icon gitlab-artifact" else "no-icon"
    "<li class='two-lines'>
      <div class='status status-added #{artifactIcon}'></div>
      <div class='primary-line icon gitlab-#{job.status}'>
        #{job.name}
        <i class='text-muted'> ♨︎ #{@controller.toHHMMSS(job.duration)}</i>
        <span class='pull-right text-muted'>#{job.id}</span>
      </div>
      <div class='secondary-line no-icon'>
        <div class='block'>
          <progress class='inline-block progress-#{type}' max='#{@maxDuration}' value='#{job.duration}'></progress>
        </div>
        <span class=''> #{moment(job.created_at).format('lll')}  - #{moment(job.finished_at).format('lll')} </span>
        <span class='icon icon-server'>#{job.runner?.description}</span>
        <img src='#{job.user?.avatar_url}' class='gitlab-avatar' /> #{job.user?.name}
    </li>"

  confirmed: (job) =>
    @cancel()
    if job.artifacts_file
      atom.confirm
        message: 'What to open?'
        detailedMessage: "Do you want to open the log or the report or both or all logs of the group #{job.name}?"
        buttons:
          Group: => @controller.openFailedLogsInGroup(@projectPath, @items, job)
          Log: => @controller.openLog(@projectPath, job)
          Report: => @controller.openReport(@projectPath, job)
          Both: =>
            @controller.openLog(@projectPath, job)
            @controller.openReport(@projectPath, job)
    else
      atom.confirm
        message: 'What to open?'
        detailedMessage: "Do you want to open the log or all logs of the group #{job.name}?"
        buttons:
          Group: => @controller.openFailedLogsInGroup(@projectPath, @items, job)
          Log: => @controller.openLog(@projectPath, job)

  cancelled: ->
    @panel.hide()

module.exports = JobSelectorView
