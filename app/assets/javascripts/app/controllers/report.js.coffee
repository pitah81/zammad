class Index extends App.ControllerContent
  constructor: ->
    super

    # check authentication
    return if !@authenticate()

    @title 'Reporting'
    @navupdate '#report'
    @startLoading()
    @ajax(
      type:  'GET',
      url:   @apiPath + '/reports/config',
      processData: true,
      success: (data) =>
        @stopLoading()
        @config = data.config
        App.Collection.load( type: 'ReportProfile', data: data.profiles )
        @render()
    )

  getParams: =>
    return @params if @params

    @params           = {}
    @params.timeRange = 'year'
    current           = new Date()
    currentDay        = current.getDate()
    currentMonth      = current.getMonth() + 1
    currentYear       = current.getFullYear()
    currentWeek       = current.getWeek()
    @params.day       = currentDay
    @params.month     = currentMonth
    @params.week      = currentWeek
    @params.year      = currentYear
    if !@params.metric
      for key, config of @config.metric
        if config.default
          @params.metric = config.name
    if !@params.backendSelected
      @params.backendSelected = {}
      for key, config of @config.metric
        for backend in config.backend
          if backend.selected
            @params.backendSelected[backend.name] = true
    if !@params.profileSelected
      @params.profileSelected = {}
      for profile in App.ReportProfile.all()
        if _.isEmpty( @params.profileSelected )
          @params.profileSelected[ profile.id ] = true
    @params

  render: (data = {}) =>

    @params = @getParams()

    @html App.view('report/main')(
      params: @params
    )

    new TimeRangePicker(
      el:     @el.find('.js-timeRangePicker')
      params: @params
      ui:     @
    )

    new TimePicker(
      el:     @el.find('.js-timePicker')
      params: @params
      ui:     @
    )

    new Sidebar(
      el:     @el.find('.sidebar')
      config: @config
      params: @params
    )

    new Graph(
      el:     @el
      config: @config
      params: @params
      ui:     @
    )

class Graph extends App.ControllerContent
  constructor: ->
    super

    # rerender view
    @bind 'ui:report:rerender', =>
      @render()

    @render()

  render: =>

    update = (data) =>
      @draw(data.data)
      t = new Date
      @el.find('#download-chart').html(t.toString())
      new Download(
        el:     @el.find('.js-dataDownload')
        config: @config
        params: @params
        ui:     @ui
      )

    url = @apiPath + '/reports/generate'
    interval = 60000
    if @params.timeRange is 'year'
      interval = 30000
    if @params.timeRange is 'month'
      interval = 20000
    if @params.timeRange is 'week'
      interval = 20000
    if @params.timeRange is 'day'
      interval = 20000
    if @params.timeRange is 'realtime'
      interval = 10000

    @ajax(
      type: 'POST'
      url:  url
      data: JSON.stringify(
        metric:    @params.metric
        year:      @params.year
        month:     @params.month
        week:      @params.week
        day:       @params.day
        timeRange: @params.timeRange
        profiles:  @params.profileSelected
        backends:  @params.backendSelected
      )
      processData: true
      success: (data) =>
        update(data)
        @delay( @render, interval, 'report-update', 'page' )
    )

  draw: (data) =>
    @log('draw', data)
    $('#placeholder').empty()

    # create xaxis
    xaxis = []
    if @params.timeRange is 'realtime'
      for minute in [0..59]
        xaxis.push [minute, '']
    else if @params.timeRange is 'day'
      for hour in [0..23]
        xaxis.push [hour, hour]
    else if @params.timeRange is 'month'
      for day in [1..31]
        xaxis.push [day, day]
    else if @params.timeRange is 'week'
      xaxis = [[1, 'Mon'], [2, 'Tue'], [3, 'Wed'], [4, 'Thr'], [5, 'Fri'], [6, 'Sat'], [7, 'Sun'] ]
    else
      xaxis = [[1, 'Jan'], [2, 'Feb'], [3, 'Mar'], [4, 'Apr'], [5, 'Mai'], [6, 'Jun'], [7, 'Jul'], [8, 'Aug'], [9, 'Sep'], [10, 'Oct'], [11, 'Nov'], [12, 'Dec']]

    dataPlot = []
    for key, value of data
      dataPlot.push {
        data: value
        label: key
      }
    # plot
    $.plot( $('#placeholder'), dataPlot, {
      yaxis: { min: 0 },
      xaxis: { ticks: xaxis }
    } )


class Download extends App.Controller
  events:
    'click .js-dataDownloadBackendSelector': 'tableUpdate'

  constructor: (data) ->

    # unbind existing click binds
    data.el.unbind('click .js-dataDownloadBackendSelector')

    super
    @render()

  render: ->

    reports = []

    # select first backend, if no backend is selected
    $('.js-backendSelector:checked').each( (index, element) ->
      if $(element).hasClass('download')
        value = $(element).val()
        reports.push value
    )

    # get used profiles
    profiles = []
    for key, value of @params.profileSelected
      if value
        if !@profileSelectedId
          @profileSelectedId = key
        profiles.push App.ReportProfile.find(key)

    @html App.view('report/download_header')(
      reports:  reports
      profiles: profiles
      metric:   @config.metric[@params.metric]
    )

    @backendSelected = ''

    active = false
    @el.find('.js-dataDownloadBackendSelector').each( (index, element) ->
      if $(element).parent().hasClass('is-active')
        active = true
    )
    if !active
      @el.find('.js-dataDownloadBackendSelector').first().parent().addClass('is-active')

    # rerender view after backend is selected
    @el.find('.js-dataDownloadBackendSelector').each( (index, element) =>
      if $(element).parent().hasClass('is-active')
        @profileSelectedId = $(element).data('profile-id')
        @backendSelected   = $(element).data('backend')
    )

    @tableUpdate()

  tableUpdate: (e) =>
    if e
      e.preventDefault()
      @el.find('.js-dataDownloadBackendSelector').parent().removeClass('is-active')
      $(e.target).parent().addClass('is-active')
      @profileSelectedId = $(e.target).data('profile-id')
      @backendSelected   = $(e.target).data('backend')

    table = (tickets, count) =>
      url = '#ticket/zoom/'
      if App.Config.get('import_mode')
        url = App.Config.get('import_otrs_endpoint') + '/index.pl?Action=AgentTicketZoom;TicketID='
      if _.isEmpty(tickets)
        @el.find('js-dataDownloadTable').html('')
      else
        html = App.view('report/download_list')(
          tickets: tickets
          count:   count
          url:     url
          download: @apiPath + '/reports/csvforset/' + name
        )
        @el.find('js-dataDownloadTable').html(html)

    @startLoading()
    @ajax(
      type:  'POST'
      url:   @apiPath + '/reports/sets'
      data: JSON.stringify(
        metric:     @params.metric
        year:       @params.year
        month:      @params.month
        week:       @params.week
        day:        @params.day
        timeRange:  @params.timeRange
        profile_id: @profileSelectedId
        backend:    @backendSelected
      )
      processData: true
      success: (data) =>
        @stopLoading()

        # load ticket collection / do not save in localStorage
        App.Collection.load( type: 'TicketReport', data: data.tickets, localStorage: true )
        ticket_collection = []

        if data.tickets
          for record in data.tickets
            ticket = App.TicketReport.fullLocal( record.id )
            ticket_collection.push ticket

        table(ticket_collection, data.count)
    )

class TimeRangePicker extends App.Controller
  events:
    'click .js-timeRange': 'select'

  constructor: ->
    super

   # rerender view
    @bind 'ui:report:rerender', =>
      @render()

    @render()

  render: =>
    @html App.view('report/time_range_picker')()

    # select time slot
    @el.find('.js-timeRange').removeClass('is-active')
    @el.find('.js-timeRange[data-type="' + @ui.params.timeRange + '"]').addClass('is-active')

  select: (e) =>
    console.log('TS click')
    e.preventDefault()
    @ui.params.timeRange = $(e.target).data('type')
    console.log 'SLOT', @ui.params.timeRange
    App.Event.trigger( 'ui:report:rerender' )


class TimePicker extends App.Controller
  events:
    'click .js-timePickerDay':   'selectTimeDay'
    'click .js-timePickerYear':  'selectTimeYear'
    'click .js-timePickerMonth': 'selectTimeMonth'
    'click .js-timePickerWeek':  'selectTimeWeek'

  constructor: ->
    super

    @_timeSlotPicker()

    # rerender view
    @bind 'ui:report:rerender', =>
      @render()

    @render()

  render: =>
    @html App.view('report/time_picker')(
      params:         @ui.params
      timeRangeDay:   @timeRangeDay
      timeRangeMonth: @timeRangeMonth
      timeRangeWeek:  @timeRangeWeek
      timeRangeYear:  @timeRangeYear
    )

    # select time slot
    @el.find('.time-slot').removeClass('is-active')
    @el.find('.time-slot[data-type="' + @ui.params.timeRange + '"]').addClass('is-active')

  selectTimeDay: (e) =>
    e.preventDefault()
    @ui.params.day = $(e.target).data('type')
    $(e.target).parent().parent().find('li').removeClass('is-active')
    $(e.target).parent().addClass('is-active')
    App.Event.trigger( 'ui:report:rerender' )

  selectTimeMonth: (e) =>
    e.preventDefault()
    @ui.params.month = $(e.target).data('type')
    $(e.target).parent().parent().find('li').removeClass('is-active')
    $(e.target).parent().addClass('is-active')
    App.Event.trigger( 'ui:report:rerender' )

  selectTimeWeek: (e) =>
    e.preventDefault()
    @ui.params.week = $(e.target).data('type')
    $(e.target).parent().parent().find('li').removeClass('is-active')
    $(e.target).parent().addClass('is-active')
    App.Event.trigger( 'ui:report:rerender' )

  selectTimeYear: (e) =>
    e.preventDefault()
    @ui.params.year = $(e.target).data('type')
    $(e.target).parent().parent().find('li').removeClass('is-active')
    $(e.target).parent().addClass('is-active')
    App.Event.trigger( 'ui:report:rerender' )

  _timeSlotPicker: ->
    @timeRangeYear = []
    year = new Date().getFullYear()
    for item in [year-2..year]
      record = {
        display: item
        value: item
      }
      @timeRangeYear.push record

    @timeRangeMonth = [
      {
        display: 'Jan'
        value: 1
      },
      {
        display: 'Feb'
        value: 2
      },
      {
        display: 'Mar'
        value: 3
      },
      {
        display: 'Apr'
        value: 4,
      },
      {
        display: 'Mai'
        value: 5,
      },
      {
        display: 'Jun'
        value: 6,
      },
      {
        display: 'Jul'
        value: 7,
      },
      {
        display: 'Aug'
        value: 8,
      },
      {
        display: 'Sep'
        value: 9,
      },
      {
        display: 'Oct'
        value: 10,
      },
      {
        display: 'Nov'
        value: 11,
      },
      {
        display: 'Dec'
        value: 12,
      },
    ]

    @timeRangeWeek = []
    for item in [1..52]
      record = {
        display: item
        value: item
      }
      @timeRangeWeek.push record

    @timeRangeDay = []
    for item in [1..31]
      record = {
        display: item
        value: item
      }
      @timeRangeDay.push record


class Sidebar extends App.Controller
  events:
    'click .js-profileSelector': 'selectProfile'
    'click .js-backendSelector': 'selectBackend'
    'click .panel-title':        'selectMetric'

  constructor: ->
    super
    @render()

  render: =>

    metrics = @config.metric
    profiles = App.ReportProfile.all()
    console.log('Si', @params)
    @html App.view('report/sidebar')(
      metrics:  metrics
      params:   @params
      profiles: profiles
    )

  selectMetric: (e) =>
    return if $(e.target).closest('.panel').find('.collapse.in').get(0)
    metric = $(e.target).closest('.panel').data('metric')
    return if @params.metric is metric
    @params.metric = metric
    App.Event.trigger( 'ui:report:rerender' )

  selectProfile: (e) =>
    profile_id = $(e.target).val()
    active = $(e.target).prop('checked')
    if active
      @params.profileSelected[profile_id] = true
    else
      delete @params.profileSelected[profile_id]
    App.Event.trigger( 'ui:report:rerender' )

  selectBackend: (e) =>
    backend = $(e.target).val()
    active = $(e.target).prop('checked')
    if active
      @params.backendSelected[backend] = true
    else
      delete @params.backendSelected[backend]
    App.Event.trigger( 'ui:report:rerender' )

App.Config.set( 'report', Index, 'Routes' )
App.Config.set( 'Reporting', { prio: 8000, parent: '', name: 'Reporing', translate: true, target: '#report', icon: 'report', role: ['Report'] }, 'NavBarRight' )