
#include <random>
#include "graphics/programs/path_tracer_program.hpp"
#include "controls/user_controller.hpp"
#include "scene/scene.hpp"
#include "scene/hittables/hittable_sphere.hpp"
#include "scene/hittables/hittable_list.hpp"
#include "scene/cornell_box_scene.hpp"
#include "graphics/programs/present_program.hpp"
#include "scene/materials/material_lambertian.hpp"
#include "scene/scene_drawer.hpp"
#include "utils/frame_timer.hpp"
#include "scene/build_model.hpp"
#include "scene/materials/material_dielectric.hpp"

void app() {
    const int width = 1000;
    const int height = 1000;

    sf::ContextSettings settings;
    settings.majorVersion = 4;
    settings.minorVersion = 1;

    auto* window = new sf::RenderWindow(sf::VideoMode(width, height, 32), "Tracer",
                            sf::Style::Titlebar | sf::Style::Close, settings);

    window->setVerticalSyncEnabled(true);
    window->setFramerateLimit(60);
    window->setActive(true);

    glewInit();

    Graphics::Camera camera;
    UserController controller(&camera, window, nullptr);

    Scene* scene = cornell_box_scene();
    SceneDrawer drawer(scene, &camera, width, height);
    FrameTimer timer;

//    auto* model = new HittableList();
//    build_model(model, "resources/models/bobs.obj",
//                Matrix4f::rotation_x_matrix(M_PI / 2) *
//                Matrix4f::translation_matrix(1, 0, -1),
//                new MaterialLambertian({1, 0.874, 0.768}));
//    scene->get_root_hittable()->add_children(model);

    scene->get_root_hittable()->add_children(
        new HittableSphere({0, 0, -2}, 2,
           new MaterialDielectric({1, 0.874, 0.768}, 2, -1, 0)
       )
    );

    camera.set_position({-15, 0, 0});
    camera.set_focus_distance(2);
    camera.set_camera_width((float)window->getSize().x / (float)window->getSize().y);

    drawer.get_post_processing_program()->set_brightness(2.0);
    drawer.get_post_processing_program()->set_gamma(0.4);

    sf::Event event {};

    int frames_logging = 5;

    while(true) {

        while (window->pollEvent(event)) controller.handle_event(event);

        if(!window->isOpen()) break;
        controller.tick();

        if(controller.poll_screenshot()) {
            drawer.take_screenshot();
            std::cout << "Screenshot queried\n";
        }

        drawer.set_dynamic_mode(camera.is_moved());

        timer.begin_frame();
        drawer.draw_chunk();
        drawer.present();

        window->display();

        timer.end_frame();

        if(drawer.get_frames() % frames_logging == 0 && drawer.get_frame_substep() == 0) {
            double rays_per_second = (double) frames_logging * (double) drawer.get_frame_rays() / timer.flush();

            std::cout << "completed frame " << drawer.get_frames() << ", ";
            std::cout << (long long) rays_per_second << " rays per second, ";
            std::cout << (long long) drawer.get_frames() * (long long) drawer.get_frame_rays() << " rays in total\n";
        }
    }

    delete window;
}
int main() {
//    app();
//    try {
        app();
//    } catch(GLException &ex) {
//        std::cout << "GLException: " << ex.what() << "\n";
//    } catch(GLStringException &ex) {
//        std::cout << "GLStringException: " << ex.what() << "\n";
//    }
}