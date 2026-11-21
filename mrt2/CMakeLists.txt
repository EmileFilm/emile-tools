# mrt2: Émile's offline front end to magentart::core (main.cpp).
# build.sh copies this folder into the Magenta RealTime repo and adds it there.
add_executable(mrt2 main.cpp)
target_link_libraries(mrt2 PRIVATE magentart::core)
