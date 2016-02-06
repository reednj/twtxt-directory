// Basic javascript Class object. No inheritance or anything like that
// but allows the nice encapsulation of properties and methods.
//
// Takes as its only argument an object with a set of methods for the 
// class. If there is a method called initialize, it will be used as the
// constructor.
//
// Usage:
//
// var Logger = new Class({
//   initialize: function(name) {
//     this.name = name;
//     console.log('init: ' + this.name);
//   },
//   
//   log: function(txt) {
//     console.log('log ' + this.name + ': ' + txt);
//   }
// });
//
var Class = function (obj) {
    obj = obj || {};

    var $Class = function () {
        var emptyFn = (function () { });
        (obj.initialize || emptyFn).apply(this, arguments);
    };

    for (k in obj) {
        if (obj.hasOwnProperty(k)) {
            var fn = obj[k];
            if (typeof fn == 'function') {
                $Class.prototype[k] = fn;
            }
        }
    };

    return $Class;
};

(function () {
	

	var implement = function(name, fn) {
		if(!this.prototype[name])
			this.prototype[name] = fn;

		return this;
	};

	if(!Function.prototype.implement) {
		Function.prototype.implement = implement;
	}

	if(!Element.prototype.implement) {
		Element.implement = implement;
		Element.prototype.implement = implement;
	}

})();

(function() {
	Function.implement('delay', function(time_ms, scope) {
		return setTimeout(this.bind(scope), time_ms);
	});

	Function.implement('periodical', function(time_ms, scope) {
		return setInterval(this.bind(scope), time_ms);
	});
})();