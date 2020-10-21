using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Lang;
using Toybox.Application;
using Toybox.Time.Gregorian;
using Toybox.Time;
using Toybox.Math;

enum {
	SUN_DOWN = 0,
	SUN_RISE = 1,
	SUN_SET = 2,
	SUN_DUSK = 3
}

class NearestEvent
{
	var is_set;
	var tl;
	var setrise;
	function initialize(iss, twilight, main_event)
	{
		is_set = iss;
		tl = twilight;
		setrise = main_event;
	}
}

class TarasFaceView extends WatchUi.WatchFace
{
	var latitude;
	var longitude;
    function initialize()
    {
    	latitude = Application.getApp().getProperty("Latitude");
    	longitude = Application.getApp().getProperty("Longitude");
        WatchFace.initialize();
    }

    function onLayout(dc)
    {
        setLayout(Rez.Layouts.WatchFace(dc));
    }

    function onShow()
    {

    }

	function getDayOneWeekOne(year)
	{
		var options = {
		    :year   => year,
		    :month  => 1,
		    :day    => 1
		};
		var soy = Gregorian.moment(options);
		var dow = Gregorian.info(soy, Time.FORMAT_SHORT).day_of_week - 1;
		if(Gregorian.info(soy, Time.FORMAT_SHORT).day_of_week == 0)
		{
			dow = 6;
		}
		return soy.add(new Time.Duration((((11 - dow) % 7) - 3) * Gregorian.SECONDS_PER_DAY - System.getClockTime().timeZoneOffset));
	}

	function getWW(now)
	{
		var nfo = Gregorian.info(now, Time.FORMAT_SHORT);
		var d1w1 = getDayOneWeekOne(nfo.year);
		var yn = nfo.year;
		if (now.lessThan(d1w1))
		{
			yn = yn - 1;
			d1w1 = getDayOneWeekOne(yn);
		}
		else
		{
			var tv = getDayOneWeekOne(yn + 1);
			if(now.greaterThan(tv))
			{
				yn = yn + 1;
				d1w1 = tv;
			}
		}

		var wn = Math.floor(now.subtract(d1w1).value() / (7 * Gregorian.SECONDS_PER_DAY)) + 1;
		return wn;
	}

	function weekDay(now)
	{
		var nfo = Gregorian.info(now, Time.FORMAT_MEDIUM);
		return nfo.day_of_week;
	}
	
	function currentDate(now)
	{
		var nfo = Gregorian.info(now, Time.FORMAT_SHORT);
		return Lang.format("$1$.$2$", [nfo.day.format("%02d"), nfo.month.format("%02d")]);
	}

    function unix2julian(unixtime)
    {
    	return unixtime.value() / 86400d + 2440587.5d;
    }
    
    function julian2unix(jd)
    {
    	return new Time.Moment(((jd - 2440587.5d) * 86400d).toLong());
    }

	function modified_julian_date(unixtime)
	{
		var jd = unix2julian(unixtime);
		var mjd = Math.floor(jd - 2451545d + 0.0008d + 0.5d);
		return mjd; 
	}

	function mean_solar_noon(mjd)
	{
		return mjd - longitude / 360d;
	}

	function solar_mean_anomaly(mjd)
	{
		var angle = 357.5291d + 0.98560028d * mean_solar_noon(mjd);
		var whole_angle = Math.floor(angle).toLong();
		var fraction = angle - whole_angle;
		return (whole_angle % 360) + fraction;
	}

	function equation_of_center(mjd)
	{
	    var M = solar_mean_anomaly(mjd) * Math.PI / 180d;
	    return 1.9148d * Math.sin(M) + 0.02d * Math.sin(2*M) + 0.0003d * Math.sin(3*M);
	}

	function ecliptic_longitude(mjd)
	{
		var angle = solar_mean_anomaly(mjd) + equation_of_center(mjd) + 180d + 102.9372d;
		var whole_angle = Math.floor(angle).toLong();
		var fraction = angle - whole_angle;
		return (whole_angle % 360) + fraction;
	}
	
	function solar_transit(mjd)
	{
	    var lbd2 = 2d * ecliptic_longitude(mjd) * Math.PI / 180d;
	    var M = solar_mean_anomaly(mjd) * Math.PI / 180d;
	    return 2451545d + mean_solar_noon(mjd) + 0.0053d * Math.sin(M) - 0.0069d * Math.sin(lbd2);
	}

	function declination_of_sun(mjd)
	{
		return Math.sin(ecliptic_longitude(mjd) * Math.PI / 180d) * Math.sin(23.44d * Math.PI / 180d);
	}

	function hour_angle(mjd)
	{
	    var sin_delta = declination_of_sun(mjd);
	    var cos_delta = Math.sqrt(1 - sin_delta * sin_delta);
	    var lat = latitude * Math.PI / 180d;
	    return Math.acos((Math.sin(-0.83d * Math.PI / 180d) - (Math.sin(lat) * sin_delta)) / (Math.cos(lat) * cos_delta));
	}

	function getSunEvent(event_type, current_time)
	{
		var mjd = modified_julian_date(current_time);
    	var ang;
    	
    	if((event_type == SUN_DOWN) || (event_type == SUN_DUSK))
    	{
    		ang = 18d * Math.PI / 180d;
    	}
    	else
    	{
    		ang = 0d;
    	}
    	
    	var set_dusk = 1;
    	if((event_type == SUN_DOWN) || (event_type == SUN_RISE))
    	{
    		set_dusk = -1;
    	}	

		return julian2unix(solar_transit(mjd) + set_dusk * ((hour_angle(mjd) + ang) / (2d * Math.PI)));
	}

	function getNearestSunEvent(current_time)
	{
		var dusk = getSunEvent(SUN_DUSK, current_time);
		if(current_time.greaterThan(dusk))
		{
			var next_day = current_time.add(new Time.Duration(Gregorian.SECONDS_PER_DAY));
			var down_moment = getSunEvent(SUN_DOWN, next_day);
			var rise_moment = getSunEvent(SUN_RISE, next_day);
			var down = Gregorian.info(down_moment, Time.FORMAT_SHORT);
			var rise = Gregorian.info(rise_moment, Time.FORMAT_SHORT);
			return new NearestEvent(false, down, rise);
		}
		else
		{
			var rise = getSunEvent(SUN_RISE, current_time);
			if(current_time.greaterThan(rise))
			{
				var set = Gregorian.info(getSunEvent(SUN_SET, current_time), Time.FORMAT_SHORT);
				return new NearestEvent(true, Gregorian.info(dusk, Time.FORMAT_SHORT), set);
			}
			else
			{
				var down = Gregorian.info(getSunEvent(SUN_DOWN, current_time), Time.FORMAT_SHORT);
				var rise = Gregorian.info(getSunEvent(SUN_RISE, current_time), Time.FORMAT_SHORT);
				return new NearestEvent(false, down, rise);
			}
		}
	}

    function onUpdate(dc)
    {
        var clockTime = System.getClockTime();
        var now = Time.now();
        var view;

//        view = View.findDrawableById("HoursLabel");
//        view.setText(clockTime.hour.format("%02d"));
//        view = View.findDrawableById("MinutesLabel");
//        view.setText(clockTime.min.format("%02d"));
//        view = View.findDrawableById("SecondsLabel");
//        view.setText(clockTime.sec.format("%02d"));
        
        view = View.findDrawableById("HoursLabel");
        view.setText(clockTime.hour.format("%02d"));
        view = View.findDrawableById("MinutesLabel");
        view.setText(":");
        view = View.findDrawableById("SecondsLabel");
        view.setText(clockTime.min.format("%02d"));

		view = View.findDrawableById("WWLabel");
        view.setText(Lang.format(WatchUi.loadResource(Rez.Strings.WWfmt), [getWW(now).format("%02d")]));
        view = View.findDrawableById("WeekdayLabel");
        view.setText(weekDay(now));
        view = View.findDrawableById("DateLabel");
        view.setText(currentDate(now));
		var near_event = getNearestSunEvent(now);
		if(near_event.is_set == true)
		{
			view = View.findDrawableById("SunLabel1");
			view.setText(Lang.format(WatchUi.loadResource(Rez.Strings.SunSetFmt),
				[near_event.setrise.hour.format("%02d"), near_event.setrise.min.format("%02d")]));
			view = View.findDrawableById("SunLabel2");	
			view.setText(Lang.format(WatchUi.loadResource(Rez.Strings.SunDuskFmt),
				[near_event.tl.hour.format("%02d"), near_event.tl.min.format("%02d")]));
					
		}
		else
		{
			view = View.findDrawableById("SunLabel1");
			view.setText(Lang.format(WatchUi.loadResource(Rez.Strings.SunDownFmt),
				[near_event.tl.hour.format("%02d"), near_event.tl.min.format("%02d")]));
			view = View.findDrawableById("SunLabel2");
			view.setText(Lang.format(WatchUi.loadResource(Rez.Strings.SunRiseFmt),
				[near_event.setrise.hour.format("%02d"), near_event.setrise.min.format("%02d")]));
		}
        
        View.onUpdate(dc);
        
    }

    function onHide()
    {
   
    }

    function onExitSleep()
    {

    }

    function onEnterSleep()
    {

    }
}
