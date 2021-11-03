/*
 the aim of this file is to setup the schemas and tables,
 create cleanup functions, startup functions and
 populate the tables with some dummy data as well.
 */


/*
 delete all previous schemas, tables and data to start off with a clean database
 */
drop schema if exists
    academic_data,
    course_offerings,
    faculty_actions,
    admin_data,
    student_grades,
    registrations,
    adviser_actions
    cascade;

/*
 create the required schemas which will have tables and some custom dummy data
 */
create schema academic_data; -- for general academic data
create schema admin_data;
create schema faculty_actions;
create schema adviser_actions;
create schema student_grades; -- for final grades of the student for all the courses taken to generate C.G.P.A.
create schema course_offerings; -- for course offered in the particular semester and year
create schema registrations;

-- will contain information regarding student registration and tickets

-- five departments considered, can be scaled up easily
create table academic_data.departments
(
    dept_name varchar primary key
);

-- stores current 
create table academic_data.semester
(
    semester integer not null,
    year integer not null,
    primary key (semester, year)
);

grant select on academic_data.semester to PUBLIC;
INSERT INTO academic_data.semester VALUES(0,0); -- default

insert into academic_data.departments (dept_name)
values ('cse'), -- computer science and engineering
       ('me'), -- mechanical engineering
       ('ee'), -- civil engineering
       ('ge'), -- general
       ('sc'), -- sciences
       ('hs') -- humanities
;

-- undergraduate curriculum implemented only
create table academic_data.degree_info
(
    degree_type varchar primary key,
    program_electives_credits integer,
    open_electives_credits integer
);
insert into academic_data.degree_info
values ('btech', 6, 18); -- bachelors degree only

create table academic_data.course_catalog
(
    course_code        varchar primary key,
    dept_name          varchar not null,
    credits            real not null,
    credit_structure   varchar not null,
    course_description varchar   default '',
    pre_requisites     varchar[] default '{}',
    foreign key (dept_name) references academic_data.departments (dept_name)
);

-- todo: populate course catalog with dummy data from csv file
create table academic_data.student_info
(
    roll_number  varchar primary key,
    student_name varchar not null,
    department   varchar not null,
    batch_year   integer not null,
    foreign key (department) references academic_data.departments (dept_name)
);
-- todo: populate student info with dummy list of students from csv file

create table academic_data.faculty_info
(
    faculty_id   varchar primary key,
    faculty_name varchar not null,
    department   varchar not null,
    foreign key (department) references academic_data.departments (dept_name)
);
-- todo: populate faculty info with dummy list of faculties from csv file

create table academic_data.adviser_info
(
    adviser_id varchar primary key ,
    batch_dept varchar,
    batch_year integer
);
-- dept_year

create table academic_data.ug_batches
(
    dept_name varchar,
    batch_year integer,
    adviser_f_id varchar,
    foreign key(adviser_f_id) REFERENCES academic_data.adviser_info(adviser_id),
    PRIMARY KEY (dept_name, batch_year)
);

create table academic_data.timetable_slots
(
    slot_name varchar primary key
);

insert into academic_data.timetable_slots values(1);
insert into academic_data.timetable_slots values(2);
insert into academic_data.timetable_slots values(3);
insert into academic_data.timetable_slots values(4);
insert into academic_data.timetable_slots values(5);
insert into academic_data.timetable_slots values(6);
insert into academic_data.timetable_slots values(7);

grant usage on schema registrations to public;
-- grant select on all tables in schema registrations to public;
grant usage on schema course_offerings to public;
grant select, references on all tables in schema course_offerings to public;
grant usage on schema academic_data to public;
grant select, references on all tables in schema academic_data to public;
grant usage on schema student_grades to public;

create or replace function course_offerings.create_registration_table()
returns trigger as
$$
declare
semester integer;
year integer;
f_id varchar;
curr_user varchar;
begin
    select academic_data.semester.semester, academic_data.semester.year from academic_data.semester into semester, year;
    execute('create table registrations.'||new.course_code||'_'||year||'_'||semester||' '||
    '(
        roll_number varchar not null,
        grade integer default 0,
        foreign key(roll_number) references academic_data.student_info(roll_number)
    );');
    select current_user into curr_user;
    foreach f_id in array new.instructors
    loop
        if f_id=curr_user then continue;
        end if;
        execute('grant select, update on registrations.'||new.course_code||'_'||year||'_'||semester||' to '||f_id||' with grant option;');
    end loop;
    return new;
end;
$$language plpgsql;

------------------------------------------------------------------------------------------------------------------------------------------------
create or replace function admin_data.add_new_semester(academic_year integer, semester_number integer)
    returns void as
$function$
declare
    -- iterator to run through all the faculties' ids
    faculty_cursor cursor for select faculty_id from academic_data.faculty_info;
    adviser_cursor cursor for select adviser_id from academic_data.adviser_info;
    student_cursor cursor for select roll_number from academic_data.student_info;
    declare f_id         academic_data.faculty_info.faculty_id%type;
    declare adviser_f_id academic_data.adviser_info.adviser_id%type;
    declare s_rollnumber academic_data.student_info.roll_number%type;
begin
    -- assuming academic_year = 2021 and semester_number = 1
    -- will create table course_offerings.sem_2021_1 which will store the courses being offered that semester
    update academic_data.semester set semester=semester_number, year=academic_year where true;
    execute ('create table course_offerings.sem_' || academic_year || '_' || semester_number || ' '||'
            (
                    course_code     varchar primary key,
                    course_coordinator varchar not null, -- tickets to be sent to course coordinator only
                    instructors     varchar[] not null,
                    slot            varchar,
                    allowed_batches varchar[] not null, -- will be combination of batch_year and department: cse_2021
                    cgpa_req        real default 0,
                    foreign key (course_code) references academic_data.course_catalog (course_code)
            );'
        );
    execute(format($s$grant select on course_offerings.sem_%s_%s to public;$s$, academic_year, semester_number));
    execute('create trigger trigger_sem_'||academic_year||'_'||semester_number||' '||'after insert on course_offerings.sem_' || academic_year || '_' || semester_number
                ||' for each row execute function course_offerings.create_registration_table();');

    execute ('create table registrations.provisional_course_registrations_' || academic_year || '_' || semester_number || ' '||'
                (   
                    roll_number     varchar not null,
                    course_code     varchar,
                    foreign key (course_code) references academic_data.course_catalog (course_code),
                    foreign key (roll_number) references academic_data.student_info (roll_number),
                    primary key (roll_number, course_code)
                );' ||
             'create trigger ensure_valid_registration
                before insert
                on registrations.provisional_course_registrations_' || academic_year || '_' || semester_number || ' '||'
                for each row
             execute function check_register_for_course();'
        );

    execute(format($s$grant select on registrations.provisional_course_registrations_%s_%s to public;$s$, academic_year, semester_number));

    execute('create table registrations.dean_tickets_'||academic_year||'_'||semester_number||' '||
       '(roll_number varchar not null,
        course_code varchar not null,
        dean_decision boolean,
        faculty_decision boolean,
        adviser_decision boolean,
        foreign key (course_code) references academic_data.course_catalog (course_code),
        foreign key (roll_number) references academic_data.student_info (roll_number),
        primary key (roll_number, course_code));
    ');
    open student_cursor;
    loop
        fetch student_cursor into s_rollnumber;
        exit when not found;
        -- execute('grant select on course_offerings.sem_'||academic_year||'_'||semester_number||' to '||s_rollnumber||';');
        execute('grant select, insert on registrations.provisional_course_registrations_'||academic_year||'_'||semester_number||' to '||s_rollnumber||';');
        execute('grant select on registrations.dean_tickets_'||academic_year||'_'||semester_number||' to '||s_rollnumber||';');
    end loop;
    close student_cursor;

    open faculty_cursor;
    loop
        fetch faculty_cursor into f_id;
        exit when not found;
        -- store the tickets for a faculty in that particular semester
        execute(format('grant select on all tables in schema student_grades to %s;', f_id));
        execute('grant select, insert on registrations.provisional_course_registrations_'||academic_year||'_'||semester_number||' to '||f_id||';');
        execute ('create table registrations.faculty_ticket_' || f_id || '_' || academic_year || '_' || semester_number ||' '||
                 '(
                     roll_number varchar not null,
                     course_code varchar not null,
                     status boolean,
                     foreign key (course_code) references academic_data.course_catalog (course_code),
                     foreign key (roll_number) references academic_data.student_info (roll_number),
                     primary key (roll_number, course_code)
                 );'
            );
        execute(format($d$create trigger faculty_ticket_trigger_%s_%s_%s before insert on registrations.faculty_ticket_%s_%s_%s for each row
            execute function check_instructor_match('%s')$d$, f_id, academic_year, semester_number, f_id, academic_year, semester_number, f_id));
        execute('grant all privileges on registrations.faculty_ticket_' || f_id || '_' || academic_year || '_' ||semester_number ||' to '||f_id||';');
        execute('grant insert on course_offerings.sem_'||academic_year||'_'||semester_number||' to '||f_id||';');

        open student_cursor;
        loop
            fetch student_cursor into s_rollnumber;
            exit when not found;
            execute format('grant select, insert on registrations.faculty_ticket_'||f_id||'_'||academic_year||'_' || semester_number ||' to '||s_rollnumber||';');
        end loop;
        close student_cursor;
    end loop;
    close faculty_cursor;

    -- create adviser tables
    open adviser_cursor;
    loop
        fetch adviser_cursor into adviser_f_id;
        exit when not found;
        -- store the tickets for a adviser in that particular semester
        execute ('create table registrations.adviser_ticket_' || adviser_f_id || '_' || academic_year || '_' || semester_number ||
                    ' (
                        roll_number varchar not null,
                        course_code varchar not null,
                        status boolean,
                        foreign key (course_code) references academic_data.course_catalog (course_code),
                        foreign key (roll_number) references academic_data.student_info (roll_number),
                        primary key (roll_number, course_code)
                    );'
            );
        execute(format($d$create trigger adviser_ticket_trigger_%s_%s_%s before insert on registrations.adviser_ticket_%s_%s_%s for each row
            execute function check_adviser_match('%s')$d$, adviser_f_id, academic_year, semester_number, adviser_f_id, academic_year, semester_number, adviser_f_id));
        execute('grant all privileges on registrations.adviser_ticket_' || adviser_f_id || '_' || academic_year || '_' ||semester_number ||' to '||adviser_f_id||';');
        open student_cursor;
        loop
            fetch student_cursor into s_rollnumber;
            exit when not found;
            execute format('grant select, insert on registrations.adviser_ticket_'||adviser_f_id||'_'||academic_year||'_' || semester_number ||' to '||s_rollnumber||';');
        end loop;
        close student_cursor;
    end loop;
    close adviser_cursor;
end;
$function$ language plpgsql;
------------------------------------------------------------------------------------------------------------------------------------------------
create or replace function admin_data.create_student() returns trigger
as
$function$
declare
pswd varchar:='123';
begin
--     create user roll_number password roll_number;
    execute format('create user %I password %L;', new.roll_number, pswd);
    execute ('create table student_grades.student_' || new.roll_number || ' '||'
                (
                    course_code     varchar not null,
                    semester        integer not null,
                    year            integer not null,
                    grade           integer not null default ''0'',
                    foreign key (course_code) references academic_data.course_catalog (course_code),
                    primary key(course_code, semester, year)
            );' ||
             'grant select on student_grades.student_' || new.roll_number || ' to ' || new.roll_number || ';'
        );
    return new;
end;
$function$ language plpgsql;
create trigger generate_student_record
    after insert
    on academic_data.student_info
    for each row
execute function admin_data.create_student();
------------------------------------------------------------------------------------------------------------------------------------------------
-- creating a faculty
create or replace function admin_data.create_faculty() returns trigger
as
$function$
declare
pswd varchar:='123';
begin
    --  create user faculty_id password faculty_id;
    execute format('create user %I password %L;', new.faculty_id, pswd);
    execute format('grant usage on schema faculty_actions to %s;', new.faculty_id);
    execute format('grant execute on all functions in schema faculty_actions to %s;', new.faculty_id);
    execute format('grant execute on all procedures in schema faculty_actions to %s;', new.faculty_id);
    execute format('grant execute on all functions in schema course_offerings to %s;', new.faculty_id);
    execute format('grant execute on all procedures in schema course_offerings to %s;', new.faculty_id);
    execute format('grant create on schema registrations to %s;', new.faculty_id);
    execute format('grant select on all tables in schema student_grades to %s;', new.faculty_id);
    return new;
end;
$function$ language plpgsql ;

create trigger generate_faculty_record
    after insert
    on academic_data.faculty_info
    for each row
execute function admin_data.create_faculty();
------------------------------------------------------------------------------------------------------------------------------------------------
-- creating a faculty
create or replace function admin_data.create_adviser() returns trigger
as
$function$
declare
pswd varchar:='123';
begin
--     create user faculty_id password faculty_id;
    execute format('create user %I password %L;', new.adviser_id, pswd);
    execute format('grant usage on schema adviser_actions to %s;', new.adviser_id);
    execute format('grant execute on all procedures in schema adviser_actions to %s;', new.adviser_id);
    execute format('grant execute on all functions in schema adviser_actions to %s;', new.adviser_id);
    execute format('grant select on all tables in schema student_grades to %s;', new.adviser_id);
    return new;
end;
$function$ language plpgsql ;

-- todo: to be added to the dean actions later so that only dean's office creates new students
create trigger generate_adviser_record
    after insert
    on academic_data.adviser_info
    for each row
execute function admin_data.create_adviser();

-- get the credit limit for a given roll number
create or replace function get_grades_list(roll_number varchar)
returns table (
    course_code varchar,
    semester    integer,
    year        integer,
    grade       integer
) as
$$
begin
    return query execute(format('select * from student_grades.student_%s;', roll_number));
end;
$$ language plpgsql;

-- obtain credit limit
create or replace function get_credit_limit(roll_number varchar)
    returns real as
$$
declare
    current_semester    integer;
    current_year        integer;
    course_id         varchar;
    courses_to_consider varchar[];
    credits_taken       real;
begin
    select semester, year from academic_data.semester into current_semester, current_year;
    if current_semester = 2
    then
        -- even semester
        courses_to_consider = array_append(courses_to_consider, (select grades_list.course_code
                                                                 from get_grades_list(roll_number) as grades_list
                                                                 where grades_list.semester = 1
                                                                   and grades_list.year = current_year));
        courses_to_consider = array_append(courses_to_consider, (select grades_list.course_code
                                                                 from get_grades_list(roll_number) as grades_list
                                                                 where grades_list.semester = 2
                                                                   and grades_list.year = current_year - 1));
    else
        -- odd semester
        courses_to_consider = array_append(courses_to_consider, (select grades_list.course_code
                                                                 from get_grades_list(roll_number) as grades_list
                                                                 where grades_list.semester = 1
                                                                   and grades_list.year = current_year - 1));
        courses_to_consider = array_append(courses_to_consider, (select grades_list.course_code
                                                                 from get_grades_list(roll_number) as grades_list
                                                                 where grades_list.semester = 2
                                                                   and grades_list.year = current_year - 1));
    end if;
    credits_taken = 0;
    foreach course_id in array courses_to_consider
        loop
            credits_taken = credits_taken + (select academic_data.course_catalog.credits FROM academic_data.course_catalog
                                             where academic_data.course_catalog.course_code = course_id);
        end loop;
    if credits_taken = 0
    then
        return 20;  -- default credit limit
    else
        return (credits_taken * 1.25) / 2; -- calculated credit limit
    end if;
end;
$$ language plpgsql;

------------------------------------------------------------------------------------------------------------------------------------------------
-- assumed: registrations.coursecode_year_sem tables to be generated by trigger on course_offerings and access granted to the faculty
create or replace function admin_data.populate_registrations() returns void as
$function$
declare
    provisional_reg_cursor refcursor;
    reg_table_row record;
    year integer;
    semester integer;
    prov_reg_name text;
    row record;
    faculty_list varchar[];
begin
    -- iterate or provisional registration and dean ticket table
    select academic_data.semester.semester, academic_data.semester.year from academic_data.semester into semester, year;
    prov_reg_name := 'registrations.provisional_course_registrations_' || year || '_' || semester||' ';

    for row in execute format('select * from %I;', prov_reg_name)
    loop
    execute('insert into registrations.'||row.course_code||'_'||year||'_'||semester||' '||'values('''||row.roll_number||''', 0);'); -- roll_number, grade
    end loop;
end;
$function$ language plpgsql;

------------------------------------------------------------------------------------------------------------------------------------------------
-- run to get all tickets
create or replace function admin_data.get_tickets() returns void as
$function$
declare
row record;
f_row record;
adv_id varchar;
sem integer;
yr integer;
st_roll varchar;
st_dept varchar;
st_year integer;
faculty_permission boolean;
advisor_permission boolean;
begin
    select semester, year from academic_data.semester into sem, yr;
    for f_row in execute(format('select * from academic_data.faculty_info;'))
    loop
        for row in execute(format('select * from registrations.faculty_ticket_%s_%s_%s;', f_row.faculty_id, yr, sem))
        loop
            faculty_permission:=row.status;
            execute format('select department, batch_year from academic_data.student_info where roll_number=''%s'';',row.roll_number) into st_dept,st_year;
            select adviser_f_id from academic_data.ug_batches where dept_name=st_dept and batch_year=st_year into adv_id;
            execute format('select status from registrations.adviser_ticket_'||adv_id||'_'||yr||'_'||sem||' where roll_number=''%s'' and course_code=''%s'';',
                row.roll_number,row.course_code) into advisor_permission;
            execute format($d$insert into registrations.dean_tickets_%s_%s values('%s','%s',%s,%s,%s);$d$,yr, sem, row.roll_number, row.course_code, null, faculty_permission, advisor_permission);
        end loop;
    end loop;
end;
$function$ language plpgsql;
------------------------------------------------------------------------------------------------------------------------------------------------
-- used by admin to update tickets
create or replace function admin_data.update_ticket(stu_rollnumber varchar, course varchar,new_status boolean) returns void as
$function$
declare
f_id varchar;
sem integer;
yr integer;
tbl_name varchar;
begin
    select current_user into f_id;
    select semester, year from academic_data.semester into sem, yr;
    tbl_name:=format('registrations.dean_tickets_%s_%s', yr, sem);
    execute format($dyn$update %s set status=%s where course_code='%s' and roll_number='%s';$dyn$, tbl_name,new_status,course,stu_rollnumber);
    if new_status=true then
        execute format($i$insert into registrations.%s_%s_%s values('%s',0);$i$, stu_rollnumber);
        raise notice 'Admin: Student % registered for course %.',stu_rollnumber, course;
    else
        raise notice 'Admin: Ticket of student % for course % rejected.',stu_rollnumber, course;
    end if;
end;
$function$ language plpgsql;
------------------------------------------------------------------------------------------------------------------------------------------------
-- print faculty's tickets
create or replace function faculty_actions.show_tickets() returns table(roll_number varchar, course_code varchar, status boolean) as
$function$
declare
f_id varchar;
sem integer;
yr integer;
begin
    select current_user into f_id;
    select semester, year from academic_data.semester into sem, yr;
    return query execute format($dyn$select * from registrations.faculty_ticket_%s_%s_%s;$dyn$, f_id, yr, sem);
end;
$function$ language plpgsql;

-- used by faculty to update student's tickets
create or replace function faculty_actions.update_ticket(stu_rollnumber varchar, course varchar,new_status boolean) returns void as
$function$
declare
f_id varchar;
sem integer;
yr integer;
tbl_name varchar;
begin
    select current_user into f_id;
    select semester, year from academic_data.semester into sem, yr;
    tbl_name:=format('registrations.faculty_ticket_%s_%s_%s', f_id, yr, sem);
    execute format($dyn$update %s set status=%s where course_code='%s' and roll_number='%s';$dyn$, tbl_name,new_status,course,stu_rollnumber);
    raise notice 'Status for % for course % changed to %',stu_rollnumber,course,new_status;
end;
$function$ language plpgsql;
------------------------------------------------------------------------------------------------------------------------------------------------
create or replace function adviser_actions.show_tickets() returns table(roll_number varchar, course_code varchar, status boolean) as
$function$
declare
adv_id varchar;
sem integer;
yr integer;
begin
    select current_user into adv_id;
    select semester, year from academic_data.semester into sem, yr;
    return query execute format($dyn$select * from registrations.adviser_ticket_%s_%s_%s;$dyn$, adv_id, yr, sem);
end;
$function$ language plpgsql;

-- used by adviser to update student's tickets
create or replace function adviser_actions.update_ticket(stu_rollnumber varchar, course varchar, new_status boolean) returns void as
$function$
declare
adv_id varchar;
sem integer;
yr integer;
tbl_name varchar;
begin
    select current_user into adv_id;
    select semester, year from academic_data.semester into sem, yr;
    tbl_name:=format('registrations.adviser_ticket_%s_%s_%s', adv_id, yr, sem);
    execute format($dyn$update %s set status=%s where course_code='%s' and roll_number='%s';$dyn$, tbl_name, new_status, course, stu_rollnumber);
    raise notice 'Status for % for course % changed to %',stu_rollnumber,course,new_status;
end;
$function$ language plpgsql;
------------------------------------------------------------------------------------------------------------------------------------------------
create or replace function calculate_cgpa(roll_number varchar) returns real as
$fn$
declare
    total_credits real;
    scored        real;
    cgpa          real;
    course_cred   real;
    course        record;
begin
    for course in execute ('select * from student_grades.student_' || roll_number || ';')
    loop
        if course.grade != 0 then
            select credits from academic_data.course_catalog where course_code = course.course_code into course_cred;
            scored := course_cred * course.grade;
            total_credits := total_credits + course_cred;
        end if;
    end loop;
    cgpa := (scored) / total_credits;
    return cgpa;
end;
$fn$ language plpgsql;

create or replace function calculate_cgpa() returns real as
$fn$
declare
    total_credits real;
    scored        real;
    cgpa          real;
    course_cred   real;
    course        record;
    roll_number varchar;
begin
    select current_user into roll_number;
    for course in execute ('select * from student_grades.student_' || roll_number || ';')
    loop
        if course.grade != 0 then
            select credits from academic_data.course_catalog where course_code = course.course_code into course_cred;
            scored := course_cred * course.grade;
            total_credits := total_credits + course_cred;
        end if;
    end loop;
    cgpa := (scored) / total_credits;
    return cgpa;
end;
$fn$ language plpgsql;
------------------------------------------------------------------------------------------------------------------------------------------------
-- check if the faculty is offering that course or not
create or replace function check_instructor_match()
    returns trigger as
$$
declare
    student_id varchar;
    coordinator_id varchar;
    f_id varchar;
    sem integer;
    yr integer;
begin
    new.status:=null; -- protection
    f_id = tg_argv[0];
    select current_user into student_id;
    if student_id!=new.roll_number then raise notice 'Invalid roll_number'; return null; end if;
    select semester, year from academic_data.semester into sem, yr;
    execute format($e$select course_coordinator from course_offerings.sem_%s_%s where course_code='%s';$e$,yr,sem,new.course_code) into coordinator_id;
    if coordinator_id is null then raise notice 'Invalid course id'; return null; end if;
    if f_id!=coordinator_id then
        raise notice 'Faculty % is not the course coordinator for course %. Kindly send the ticket to the right instructor.',f_id,new.course_id;
        return null;
    end if;
    return new;
end;
$$ language plpgsql;

-- check if that faculty is the adviser or not
create or replace function check_adviser_match()
    returns trigger as
$$
declare
    student_id varchar;
    adv_id varchar;
    advid varchar; -- for argv
    sem integer;
    yr integer;
begin
    new.status:=null; -- protection
    advid:=tg_argv[0];
    select current_user into student_id;
    if student_id!=new.roll_number then raise notice 'Not your roll_number.'; return null; end if;
    select semester, year from academic_data.semester into sem, yr;

    select adviser_id from academic_data.adviser_info, academic_data.student_info where academic_data.adviser_info.batch_year=academic_data.student_info.batch_year
    and academic_data.adviser_info.batch_dept=academic_data.student_info.department into adv_id;

    if advid!=adv_id then raise notice 'Ticket sent to wrong adviser'; return null; end if;

    return new;
end;
$$ language plpgsql;

-- to be used by student, no argument needed
create or replace function generate_student_transcript() returns
table(course_code varchar, semester integer, year integer, grade integer)
as
$f$
declare
    student_id varchar;
begin
    select current_user into student_id;
    raise notice 'Transcript for student %', student_id;
    return query execute(format($d$select * from student_grades.student_%s;$d$, student_id));
end;
$f$language plpgsql;

create or replace function generate_student_transcript(student_id varchar) returns
table(course_code varchar, semester integer, year integer, grade integer)
as
$f$
begin
    raise notice 'Transcript for student %', student_id;
    return query execute(format($d$select * from student_grades.student_%s;$d$, student_id));
end;
$f$language plpgsql;

create or replace procedure admin_data.upload_timetable(file text)
as
$f$
declare
    sem         integer;
    yr          integer;
    course_slot record;
begin
    select semester, year from academic_data.semester into sem, yr;
    create table admin_data.temp_timetable_slots
    (
        course_code varchar,
        slot        varchar
    );
    execute (format($d$copy admin_data.temp_timetable_slots from '%s' delimiter ',' csv header;$d$), file);

    for course_slot in select * from admin_data.temp_timetable_slots
        loop
            execute (format($d$update course_offerings.sem_%s_%s set slot='%s' where course_code='%s';$d$, yr, sem,
                            course_slot.slot, course_slot.course_code));
        end loop;

    drop table admin_data.temp_timetable_slots;
end;
$f$language plpgsql;

create or replace procedure faculty_actions.offer_course(course_name text, instructor_list text[],
                                                         allowed_batches text[], cgpa_lim real)
as
$proc$
declare
    course_row record := null;
    sem        integer;
    yr         integer;
    curr_user  varchar;
begin
    select semester, year from academic_data.semester into sem, yr;
    select current_user into curr_user;
    select * from academic_data.course_catalog where course_code = course_name into course_row;
    if course_row is null then
        raise notice 'Course % does not exist in catalog.',course_name;
        return;
    end if;
    execute (format($d$insert into course_offerings.sem_%s_%s values('%s','%s','%s',null,'%s',%s)$d$, course_name,
                    curr_user, instructor_list, allowed_batches, cgpa_lim));
    raise notice 'Course % offered by faculty %.', course_name, curr_user;
end;
$proc$ language plpgsql;

create or replace procedure faculty_actions.upload_grades(grade_file text, course_name text) as
$function$
declare
    semester        integer;
    year            integer;
    temp_table_name varchar;
    reg_table_name  varchar;
begin
    select academic_data.semester.semester, academic_data.semester.year from academic_data.semester into semester, year;
    temp_table_name := 'temporary_grade_store_' || course_name || '_' || year || '_' || semester;
    reg_table_name := 'registrations.' || course_name || '_' || year || '_' || semester;
    execute (format($tbl$create table %I
    (
        roll_number varchar,
        grade integer
    );
    $tbl$, temp_table_name));
    -- execute('copy '|| temp_table_name ||' from '''|| grade_file ||''' delimiter '','' csv header;');

    execute (format($dyn$copy %I from '%s' delimiter ',' csv header;$dyn$), temp_table_name, grade_file);
    execute (format($dyn$update %I set %I.grade=%I.grade from %I where %I.roll_number=%I.roll_number;$dyn$,
                    reg_table_name, reg_table_name, temp_table_name, temp_table_name, reg_table_name, temp_table_name));

    execute format('drop table %I;', temp_table_name);
end;
$function$ language plpgsql;
---------------------------------------------------------------------------------------------------------------------------
create or replace procedure faculty_actions.update_grade(roll_number text, course text, grade integer)
as
$f$
begin

end;
$f$ language plpgsql;

create or replace procedure admin_data.release_grades()
as
$f$
declare
    sem integer;
    yr integer;
    course_offering record;
    student record;
begin
    select semester, year from academic_data.semester into sem, yr;
    for course_offering in execute(format($d$select course_code from course_offerings.sem_%s_%s;$d$,yr,sem))
    loop
        for student in execute(format($d$select * from registrations.%s_%s_%s;$d$,course_offering.course_code, yr, sem))
        loop
            execute(format($d$update student_grades.student_%s set grade=%s where course_code='%s' and semester=%s and year=%s;$d$, student.roll_number, student.grade, course_offering.course_code, sem, yr));
            raise notice 'Student % given % grade in course %.', student.roll_number, student.grade, course_offering.course_code;
        end loop;
    end loop;
end;
$f$ language plpgsql;
----------------------------------------------------------------------------------------------------------------------------
create or replace procedure admin_data.release_grades(sem integer, yr integer)
as
$f$
declare
    course_offering record;
    student record;
begin
    for course_offering in execute(format($d$select course_code from course_offerings.sem_%s_%s;$d$,yr,sem))
    loop
        for student in execute(format($d$select * from registrations.%s_%s_%s;$d$,course_offering.course_code, yr, sem))
        loop
            execute(format($d$update student_grades.student_%s set grade=%s where course_code='%s' and semester=%s and year=%s;$d$, student.roll_number, student.grade, course_offering.course_code, sem, yr));
            raise notice 'Student % given % grade in course %.', student.roll_number, student.grade, course_offering.course_code;
        end loop;
    end loop;
end;
$f$ language plpgsql;
---------------------------------------------------------------------------------------------------------------------------------------
