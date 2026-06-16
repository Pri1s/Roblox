local GameConfigs = {
	Camera = {
		MinCameraDistance = 9, -- Closest the camera can get to the fighters.
		MaxCameraDistance = 27, -- Farthest the camera can pull back from the fighters.
		DistancePerStud = 0.45, -- Camera zoom added per stud of distance between fighters.
		CameraHeightOffset = 5, -- Vertical offset placing the camera above the fighters.
		TargetHeightOffset = 3, -- Vertical offset for the point the camera looks at.
		TargetVerticalClamp = 4, -- Maximum vertical tracking difference allowed between fighters.
		TrackingResponse = 12, -- How quickly the camera follows changes in fighter positions.
	},
}

return GameConfigs
