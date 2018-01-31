{$$, SelectListView} = require 'atom-space-pen-views'
percentile = require 'percentile'
moment = require 'moment'

class AllPipelineSelectorView extends SelectListView
  initialize: (pipelines, controller, projectPath) ->
    super

    @pipelines = @doSortByDate pipelines
    @controller = controller
    @projectPath = projectPath

    @addClass('overlay from-top')
    @globalCalculate @pipelines
    @calculate @pipelines
    @setItems @pipelines
    @panel ?= atom.workspace.addModalPanel(item: this)
    @focusFilterEditor()
    $$(@extraContent(@)).insertBefore(@error)
    @handleEvents()
    @panel.show()

  getFilterKey: -> 'search'

  extraContent: (thiz) ->
    return ->
      @div class: 'block', =>
        @button outlet: 'allButton', class: 'btn btn-info', ' All', =>
          @span class: 'badge badge-small', thiz.jobs?.length
        @div class: 'btn-group', =>
          @button outlet: 'successButton', class: 'btn btn-success', ' Success', =>
            @span class: 'badge badge-small', thiz.success?.length
          @button outlet: 'unstableButton', class: 'btn btn-warning', ' Unstable', =>
            @span class: 'badge badge-small', thiz.unstable?.length
          @button outlet: 'failedButton', class: 'btn btn-error', ' Failed', =>
            @span class: 'badge badge-small', thiz.failed?.length

      @div class: 'block', =>
        @div class: 'btn-group', =>
          @button outlet: 'sortById', class: 'btn', ' Sort by id'
          @button outlet: 'sortBySha', class: 'btn', ' Sort by sha'
          @button outlet: 'sortByDate', class: 'btn', ' Sort by date'
          @button outlet: 'sortByDuration', class: 'btn', ' Sort by duration'
          @button outlet: 'sortByBranch', class: 'btn', ' Sort by branch'

  doSortByDate: (items) ->
    items.sort (a, b) ->
      if a.created_at and b.created_at
        return moment(b.created_at).diff(moment(a.created_at))
      else
        return 0

  handleEvents: ->
    @wireOutlets(@)

    @successButton.on 'mouseover', (e) =>
      @setItems @success
      @calculate @items

    @unstableButton.on 'mouseover', (e) =>
      @setItems @unstable
      @calculate @items

    @failedButton.on 'mouseover', (e) =>
      @setItems @failed
      @calculate @items

    @sortById.on 'mouseover', (e) =>
      @setItems @items.sort (a, b) ->
        return a.id - b.id

    @sortBySha.on 'mouseover', (e) =>
      @setItems @items.sort (a, b) ->
        return -1 if a.sha < b.sha
        return 1 if a.sha > b.sha
        return 0

    @sortByDate.on 'mouseover', (e) =>
      @setItems @doSortByDate @items

    @sortByDuration.on 'mouseover', (e) =>
      @setItems @items.sort (a, b) ->
        return b.duration - a.duration

    @sortByBranch.on 'mouseover', (e) =>
      @setItems @items.sort (a, b) ->
        return a.ref - b.ref

  calculate: (items) ->
    if items?.length > 0
      @maxDuration = items.reduce( ((max, p) ->
        Math.max(max, p.duration || 0)
      ), 0 )

      @averageDuration = percentile(50, items, (item) -> item.duration).duration

      success = items.filter( (p) -> p.status is 'success')
      if success?.length > 0
        @maxDurationSuccess = success?.reduce( ((max, p) ->
          Math.max(max, p.durationSuccess || 0)
        ), 0 )
        @averageDurationSuccess = percentile(50, success, (item) -> item.durationSuccess).durationSuccess

  globalCalculate: (items) ->
    if items?.length > 0
      @success = items.filter( (p) -> p.status is 'success')
      @failed = items.filter( (p) -> p.status is 'failed')
      @unstable = items.filter( (p) -> p.status is 'success' and p.loadedJobs?.filter( (j) => j.status is 'failed')?.length > 0)

  asUniqueNames: (jobs) =>
    return jobs.map((j) => j.name).unique()

  viewForItem: (pipeline) ->
    pipeline.elapsed = moment(pipeline.finished_at).diff(moment(pipeline.created_at), 'seconds')

    if pipeline.loadedJobs?.length > 0
      {alwaysSuccess, unstable, alwaysFailed, total} = @controller.statistics(pipeline.loadedJobs)

      type = @controller.toType(pipeline, @averageDuration)

      "<li class='two-lines'>
        <div class='status icon icon-git-commit'></div>
        <div class='primary-line icon gitlab-#{pipeline.status}'>
          #{pipeline.id}
          <span class='text-muted icon icon-clock'> #{moment(pipeline.created_at).format('lll')} / #{moment(pipeline.created_at).fromNow()}</span>
          <span class='pull-right'>
            <span class='text-subtle'>#{pipeline.commit?.short_id}</span>
            <span class='text-info'>#{pipeline.ref}</span>
          </span>
        </div>
        <div class='secondary-line no-icon'>
          <div class='block'>
            <span class='text-muted'>#{pipeline.commit?.title}</span>
          </div>
          <div class='block'>
            <progress class='inline-block progress-#{type}' max='#{@maxDuration}' value='#{pipeline.duration}'></progress>
            <i class='text-muted'> ♨︎ #{@controller.toHHMMSS(pipeline.duration)}</i>
            <span class='text-warning'> / ABS #{@controller.toHHMMSS(pipeline.elapsed)}</span>
          </div>
          <span class='text-success'>#{@asUniqueNames(alwaysSuccess)}</span>
          <div class='block'>
            <span class='text-warning'>#{@asUniqueNames(unstable)}</span>
          </div>
          <div class='block'>
            <span class='text-error'>#{@asUniqueNames(alwaysFailed)}</span>
          </div>
          <span class='badge badge-info'>#{total.length}</span>
          <span class='badge badge-success'>#{alwaysSuccess.length}</span>
          <span class='badge badge-warning'>#{unstable.length}</span>
          <span class='badge badge-error'>#{alwaysFailed.length}</span>
          <span class='pull-right'>
            <img src='#{pipeline.user?.avatar_url}' class='gitlab-avatar' /> #{pipeline.user?.name}
          </span>
      </li>"
    else
      "<li class='two-lines'>
        <div class='status status-added icon icon-git-commit'></div>
        <div class='primary-line icon gitlab-#{pipeline.status}'>
          #{pipeline.id}
          <span class='pull-right'>#{pipeline.sha}</span>
          <span class='text-muted'>#{pipeline.commit?.message}</span>
        </div>
        <div class='secondary-line no-icon'>
          <span class='loading loading-spinner-tiny inline-block'></span>
        </div>
      </li>"

  confirmed: (pipeline) =>
    @cancel()
    @controller.updatePipeline(pipeline, @projectPath);

  cancelled: ->
    @panel.hide()

module.exports = AllPipelineSelectorView
