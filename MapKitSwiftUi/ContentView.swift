import SwiftUI
import CoreLocation
import MapKit

class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    var parent: ContentView
    
    init(parent: ContentView) {
        self.parent = parent
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        parent.mapData.currentCoordinate = location.coordinate
        parent.updatePositionForCurrentLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clErr = error as? CLError, clErr.code == .denied {
            // Location services denied, show guidance to the user
            print("Location services denied")
            // You may want to display an alert or message to the user
        } else {
            // Other errors
            print("Location manager error: \(error.localizedDescription)")
        }
    }
}

class MapData: ObservableObject {
    @Published var route: MKRoute?
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var currentCoordinateIndex: Int = 0
}

struct ContentView: View {
    @StateObject var mapData = MapData()
    let locationManager = CLLocationManager()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            MapView(mapData: mapData)
            
            Button("Start Journey") {
                startJourney()
            }
        }
        .onAppear {
            locationManager.delegate = LocationManagerDelegate(parent: self)
            
            switch CLLocationManager.authorizationStatus() {
            case .notDetermined, .restricted, .denied:
                locationManager.requestWhenInUseAuthorization()
                locationManager.requestAlwaysAuthorization()
                
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.startUpdatingLocation()
                
            @unknown default:
                print("error getting location")
            }
        }
        .onReceive(timer) { _ in
            updatePositionForCurrentLocation()
        }
    }
    
    func updatePositionForCurrentLocation() {
        guard let route = mapData.route else { return }
        
        let nextCoordinateIndex = mapData.currentCoordinateIndex + 1
        guard nextCoordinateIndex < route.polyline.pointCount else { return }
        
        let nextCoordinate = route.polyline.points()[nextCoordinateIndex]
        mapData.currentCoordinate = nextCoordinate.coordinate
        mapData.currentCoordinateIndex = nextCoordinateIndex
    }
    
    func startJourney() {
        generateRoute()
    }
    
    func generateRoute() {
        let sourceLocation = CLLocationCoordinate2D(latitude: 23.0710, longitude: 72.5181)
        let destinationLocation = CLLocationCoordinate2D(latitude: 23.2599, longitude: 77.4126)
        
        let sourcePlacemark = MKPlacemark(coordinate: sourceLocation)
        let destinationPlacemark = MKPlacemark(coordinate: destinationLocation)
        
        let sourceMapItem = MKMapItem(placemark: sourcePlacemark)
        let destinationMapItem = MKMapItem(placemark: destinationPlacemark)
        
        let request = MKDirections.Request()
        request.source = sourceMapItem
        request.destination = destinationMapItem
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            guard let route = response?.routes.first else {
                return
            }
            self.mapData.route = route
        }
    }
}

struct MapView: UIViewRepresentable {
    @ObservedObject var mapData: MapData
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeOverlays(uiView.overlays)
        if let route = mapData.route {
            uiView.addOverlay(route.polyline)
            uiView.setVisibleMapRect(route.polyline.boundingMapRect, animated: true)
        }
        if let coordinate = mapData.currentCoordinate {
            if uiView.annotations.isEmpty {
                let annotation = CarAnnotation(coordinate: coordinate)
                uiView.addAnnotation(annotation)
            } else {
                // Remove the existing annotation
                if let existingAnnotation = uiView.annotations.first(where: { $0 is CarAnnotation }) {
                    uiView.removeAnnotation(existingAnnotation)
                }
                // Add a new annotation with the updated coordinate
                let annotation = CarAnnotation(coordinate: coordinate)
                uiView.addAnnotation(annotation)
            }
            
            // Center the map on the current coordinate with some padding
            let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            let region = MKCoordinateRegion(center: coordinate, span: span)
            uiView.setRegion(region, animated: true)
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.blue
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is CarAnnotation else { return nil }
            
            let identifier = "carAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKAnnotationView
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView!.image = UIImage(named: "car") // Set your custom car image here
            }
            
            if let angle = calculateAngle() {
                annotationView!.transform = CGAffineTransform(rotationAngle: CGFloat(angle.radiansToDegrees))
            }
            return annotationView
        }

        var previousAngle: Double?

        func calculateAngle() -> Double? {
            guard let route = parent.mapData.route, let coordinate = parent.mapData.currentCoordinate else { return nil }
            
            let nextCoordinateIndex = parent.mapData.currentCoordinateIndex + 1
            guard nextCoordinateIndex < route.polyline.pointCount else { return nil }
            
            let currentCoordinate = coordinate
            let nextCoordinate = route.polyline.points()[nextCoordinateIndex].coordinate
            
            let fromLatitude = currentCoordinate.latitude.degreesToRadians
            let fromLongitude = currentCoordinate.longitude.degreesToRadians
            let toLatitude = nextCoordinate.latitude.degreesToRadians
            let toLongitude = nextCoordinate.longitude.degreesToRadians
            
            let differenceLongitude = toLongitude - fromLongitude
            
            let y = sin(differenceLongitude) * cos(toLatitude)
            let x = cos(fromLatitude) * sin(toLatitude) - sin(fromLatitude) * cos(toLatitude) * cos(differenceLongitude)
            let radiansBearing = atan2(y, x)
            var degree = radiansBearing.degreesToRadians
            degree = (degree >= 0) ? degree : (360 + degree)
            
            return degree
        }


        func angleBetweenPoints(_ point1: CLLocationCoordinate2D, _ point2: CLLocationCoordinate2D) -> Double {
            let xDelta = point2.longitude - point1.longitude
            let yDelta = point2.latitude - point1.latitude
            return atan2(yDelta, xDelta).radiansToDegrees
        }

    }
}

// Custom annotation for the car icon
class CarAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

extension Double {
    var radiansToDegrees: Double { self * 180 / .pi }
    var degreesToRadians: Double { self * .pi / 180 }
}

