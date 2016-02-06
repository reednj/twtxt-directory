
var TimelineChart = new Class({
	initialize: function(element, options) {
		this.options = options || {};

		this.raw_data = this.options.data || [];
		this.element = $(element).get(0);

		this.initChart(this.raw_data);
	},

	initChart: function(raw) {
		raw_data = $(raw.reverse()).filter(function(k, v) { return v.post_year > 2004; });

		var labels = $(raw_data).map(function(k, v) { return v.post_year }).get();
		var data = $.map(raw_data, function(v) { return parseFloat(v.post_count) });
		var context = this.element.getContext('2d');

		var chart = new Chart(context).Bar({
			labels: labels,
			datasets: [
				{ fillColor : "#ddf", strokeColor : "#aaf", data: data }
			]
		},
		{
			scaleStartValue: 0
		});
	}
});

var StatusChecker = new Class({
	initialize: function(options) {
		this.options = options || {};
		this.options.onComplete = this.options.onComplete || function(){};

		this.update_url = '/user/status/' + this.options.user_id;
		this.timer_id = null;
		this.interval_ms = 2000;
		this.current_status = null;

		this.update();
	},

	update: function() {
		$.getJSON(this.update_url, this.update_complete.bind(this));
	},

	update_complete: function(data) {
		if(!data)
			return;

		// update the ui no matter what
		var state_string = data.state == 'complete' ? 'complete' : 'loading...';
		$('#js-user-state h2').html(state_string);
		$('#js-user-state > div').html(data.post_count + ' posts loaded');

		// do we make another call?
		if(data.state != 'complete') {
			this.update.delay(this.interval_ms, this);
		} else {
			this.options.onComplete(this);
		}
	},
	
	status: function() {
		return this.current_status;
	}

});
