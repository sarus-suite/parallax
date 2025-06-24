load helpers.bash

@test "Either -migrate or -rmi is specified" {
	run \
		"$PARALLAX_BINARY"
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Must specify either -migrate or -rmi" ]]
}

@test "Fails if both -migrate and -rmi are passed" {
	run \
		"$PARALLAX_BINARY" -migrate -rmi -image ubuntu:latest
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Must specify either -migrate or -rmi" ]]
}

@test "Fails if --image is missing" {
	run \
		"$PARALLAX_BINARY" -migrate
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Must specify -image" ]]
}

@test "Checks version" {
	run \
		"$PARALLAX_BINARY" -version
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Parallax version" ]]
}

@test "Usage is printed" {
	run \
	   "$PARALLAX_BINARY" -help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "OCI image migration tool" ]]
	[[ "$output" =~ "Usage" ]]
	[[ "$output" =~ "-migrate" ]]
	[[ "$output" =~ "-image" ]]
}

@test "Checks unknown flag message" {
	run \
		"$PARALLAX_BINARY" -unknownflag
	[ "$status" -ne 0 ]
	[[ "$output" =~ "flag provided but not defined" ]]
}

